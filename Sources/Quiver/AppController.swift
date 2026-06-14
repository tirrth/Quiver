import AppKit
import Combine
import SwiftUI

/// Hosts the hub's SwiftUI content but opts out of the NSMenu's vibrancy. An NSMenu renders its content
/// in a vibrant material context, which forces child controls to be vibrant and desaturates their
/// colors (an "on" switch renders white instead of accent, non-deterministically per draw). Returning
/// false from `allowsVibrancy` is the documented way for a subview of a visual-effect view to stop
/// vibrancy, so the hub's controls draw with their true colors.
private final class NonVibrantHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { false }
}

/// The application shell: owns the menu-bar status item, the hub popover, the main window, the
/// settings window, and app lifecycle. Generalized from HostsMachine's AppController so it drives
/// an arbitrary set of `UtilityModule`s instead of one hard-coded feature.
@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let manager: ModuleManager
    let settings = AppSettings()
    let uiState = AppUIState()

    private let launchesInBackground: Bool
    private var statusItem: NSStatusItem?
    /// The hub shown on left-click is a system NSMenu hosting the SwiftUI hub. Letting the system own
    /// the menu gives the native menu-bar highlight, click-away dismissal and no popover arrow for free.
    private var activeHubMenu: NSMenu?
    private var pendingMenuAction: (() -> Void)?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var allowsTermination = false
    private var permissionTimer: Timer?

    init(launchesInBackground: Bool) {
        self.launchesInBackground = launchesInBackground
        self.manager = ModuleManager(modules: AppController.makeModules())
        super.init()

        settings.errorHandler = { [weak self] message in self?.presentError(message) }
        manager.onAnyStateChange = { [weak self] in self?.updateStatusButton() }
        manager.onError = { [weak self] message in self?.presentError(message) }
    }

    /// The full set of utilities Quiver ships with. Add new modules here.
    private static func makeModules() -> [UtilityModule] {
        [
            AutoRaiseModule(),
            HostsModule(),
            KeepAwakeModule(),
            ShelfModule(),
            MirrorModule()
        ]
    }

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.verbose = settings.verboseLogging
        buildMainMenu()
        configureStatusItem()
        settings.syncOnLaunch()
        manager.restoreAll()
        updateStatusButton()
        startPermissionTimer()

        // Register the system-wide "Add to Quiver Shelf" Service so it appears in any app's right-click
        // → Services menu (the user may need to enable it in System Settings ▸ Keyboard ▸ Services).
        if let shelf = manager.module(id: "shelf") as? ShelfModule {
            NSApp.servicesProvider = shelf.serviceProvider
            NSUpdateDynamicServices()
        }

        if launchesInBackground {
            NSApp.setActivationPolicy(.accessory)
        } else {
            showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Closing the app hides to the menu bar; only an explicit "Quit Quiver" fully exits.
        guard allowsTermination else {
            hideToMenuBar()
            return .terminateCancel
        }
        manager.stopAll()
        return .terminateNow
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.updateActivationPolicyForVisibleWindows() }
    }

    // MARK: Windows

    func showMainWindow() {
        if mainWindow == nil { mainWindow = makeMainWindow() }
        closePopover()
        updateActivationPolicy(showDockIcon: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettingsWindow() {
        if settingsWindow == nil { settingsWindow = makeSettingsWindow() }
        closePopover()
        updateActivationPolicy(showDockIcon: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeMainWindow() -> NSWindow {
        let root = MainWindowView(
            manager: manager,
            settings: settings,
            uiState: uiState,
            onShowSettings: { [weak self] in self?.showSettingsWindow() }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Quiver"
        window.titlebarAppearsTransparent = false
        window.center()
        window.setFrameAutosaveName("QuiverMainWindow")
        window.contentViewController = NSHostingController(rootView: root)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 720, height: 460)
        window.delegate = self
        return window
    }

    private func makeSettingsWindow() -> NSWindow {
        let root = SettingsView(settings: settings, manager: manager)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quiver Settings"
        window.center()
        window.contentViewController = NSHostingController(rootView: root)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        return window
    }

    // MARK: Menu bar

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusImage
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Quiver"
        item.button?.target = self
        item.button?.action = #selector(statusButtonClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            showHubMenu(from: sender)
        }
    }

    /// Shows the hub as a system NSMenu anchored under the icon: the status item highlights natively,
    /// it dismisses on click-away, and there's no popover arrow. The SwiftUI hub is hosted in a single
    /// menu item; `performClick` runs the menu modally until it closes.
    private func showHubMenu(from button: NSStatusBarButton) {
        refreshModulePermissions()

        let menu = NSMenu()
        let item = NSMenuItem()
        let hosting = NonVibrantHostingView(rootView: HubPopoverView(
            manager: manager,
            settings: settings,
            onOpenApp: { [weak self] in self?.dismissHubMenu { self?.showMainWindow() } },
            onOpenModule: { [weak self] id in
                self?.dismissHubMenu { self?.uiState.selectedModuleID = id; self?.showMainWindow() }
            },
            onOpenSettings: { [weak self] in self?.dismissHubMenu { self?.showSettingsWindow() } },
            onQuit: { [weak self] in self?.dismissHubMenu { self?.quitCompletely() } },
            inMenu: true
        ))
        // An NSMenu hosts its content with a vibrant material appearance, which desaturates controls
        // (e.g. an "on" switch renders white instead of accent). Pin the hub to the concrete system
        // appearance so its controls draw with normal colors.
        hosting.appearance = NSApp.effectiveAppearance
        hosting.setFrameSize(hosting.fittingSize)
        item.view = hosting
        menu.addItem(item)

        activeHubMenu = menu
        statusItem?.menu = menu
        button.performClick(nil)     // shows the menu (native highlight + dismissal); blocks until closed
        statusItem?.menu = nil
        activeHubMenu = nil

        let action = pendingMenuAction
        pendingMenuAction = nil
        action?()
    }

    /// Closes the hub menu, then runs `action` once it has fully dismissed (so windows open cleanly).
    private func dismissHubMenu(then action: @escaping () -> Void) {
        pendingMenuAction = action
        activeHubMenu?.cancelTracking()
    }

    private func closePopover() {
        activeHubMenu?.cancelTracking()
    }

    /// Simple right-click fallback menu mirroring the popover toggles.
    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Quiver", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for module in manager.modules {
            let item = NSMenuItem(title: module.title, action: #selector(toggleModuleFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = module.id
            item.state = module.isEnabled ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Quiver…", action: #selector(openMainFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Quiver", action: #selector(quitCompletely), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil  // restore left-click popover behavior
    }

    @objc private func toggleModuleFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let module = manager.module(id: id) else { return }
        module.setEnabled(!module.isEnabled)
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Quiver", action: #selector(showAboutPanel), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Quiver", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(.separator())
        // ⌘W and ⌘Q both just close the window to the menu bar — Quiver keeps running in the
        // background. A full quit is deliberate: ⌘⇧Q here, or the menu-bar popover's Quit button.
        let closeWindow = NSMenuItem(title: "Close Window", action: #selector(hideToMenuBarFromMenu), keyEquivalent: "w")
        closeWindow.target = self
        appMenu.addItem(closeWindow)
        let closeToBar = NSMenuItem(title: "Close to Menu Bar", action: #selector(hideToMenuBarFromMenu), keyEquivalent: "q")
        closeToBar.target = self
        appMenu.addItem(closeToBar)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Quiver", action: #selector(quitCompletely), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command, .shift]
        quitItem.target = self
        appMenu.addItem(quitItem)

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: Status item appearance

    private static let statusImage: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if let image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Quiver")?
            .withSymbolConfiguration(config) {
            image.isTemplate = true
            return image
        }
        // Fallback: a simple drawn glyph.
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.labelColor.setFill()
        for y: CGFloat in [3.5, 8.5, 13.5] {
            NSBezierPath(roundedRect: NSRect(x: 2, y: y - 1, width: 14, height: 2), xRadius: 1, yRadius: 1).fill()
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()

    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        // The icon image is set once in configureStatusItem(); don't re-stamp it here (the 2s
        // permission timer calls this, and re-setting the image can disturb the native highlight).
        let enabled = manager.enabledCount
        var tip = "Quiver — \(enabled) of \(manager.modules.count) utilities on"
        if manager.hasPendingPermission { tip += " · action needed" }
        button.toolTip = tip
    }

    // MARK: Permission polling

    private func startPermissionTimer() {
        // Lightweight refresh so the "Grant permission" UI updates after the user acts in System Settings.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshModulePermissions() }
        }
    }

    private func refreshModulePermissions() {
        for module in manager.modules { module.periodicRefresh() }
        updateStatusButton()
    }

    // MARK: Activation policy (Dock icon only while a window is visible)

    private func hideToMenuBar() {
        closePopover()
        mainWindow?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        updateActivationPolicy(showDockIcon: false)
    }

    private func updateActivationPolicyForVisibleWindows() {
        let hasVisible = [mainWindow, settingsWindow].contains { $0?.isVisible == true }
        updateActivationPolicy(showDockIcon: hasVisible)
    }

    private func updateActivationPolicy(showDockIcon: Bool) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    // MARK: Errors

    private func presentError(_ message: String) {
        guard !message.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quiver"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if let window = NSApp.keyWindow ?? mainWindow ?? settingsWindow, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            updateActivationPolicy(showDockIcon: true)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            updateActivationPolicyForVisibleWindows()
        }
    }

    // MARK: Menu actions

    @objc private func showAboutPanel() {
        updateActivationPolicy(showDockIcon: true)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Quiver",
            .init(rawValue: "Copyright"): "A menu-bar utility hub. Bundles AutoRaise (GPLv3, © sbmpost)."
        ])
    }

    @objc private func openMainFromMenu() { showMainWindow() }
    @objc private func openSettingsFromMenu() { showSettingsWindow() }
    @objc private func hideToMenuBarFromMenu() { hideToMenuBar() }

    @objc private func quitCompletely() {
        allowsTermination = true
        NSApp.terminate(nil)
    }
}
