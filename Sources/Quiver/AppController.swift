import AppKit
import Combine
import SwiftUI

/// Hosts the hub's SwiftUI content but opts out of the NSMenu's vibrancy. An NSMenu renders its content
/// in a vibrant material context, which forces child controls to be vibrant and desaturates their
/// colors (an "on" switch renders white instead of accent, non-deterministically per draw). Returning
/// false from `allowsVibrancy` is the documented way for a subview of a visual-effect view to stop
/// vibrancy, so the hub's controls draw with their true colors.
final class NonVibrantHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool { false }
}

/// The application shell: owns the menu-bar status item, the hub popover, the main window, the
/// settings window, and app lifecycle. It drives
/// an arbitrary set of `UtilityModule`s instead of one hard-coded feature.
@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let manager: ModuleManager
    let settings = AppSettings()
    let uiState = AppUIState()

    private let launchesInBackground: Bool
    private var statusItem: NSStatusItem?
    /// The hub is a system NSMenu hosting the SwiftUI hub, assigned to `statusItem.menu` permanently so
    /// the system manages menu-bar tracking — native highlight, click-away dismissal, no arrow, and
    /// single-click hand-off to other status items. Its content is built lazily in `menuNeedsUpdate`.
    private let hubMenu = NSMenu()
    private var hubHosting: NSView?
    /// The Control-Center-style floating hub panel (replaces the old pop-down menu for the main icon).
    private let hubPanel = HubPanel()
    private let menuBarCoordinator = MenuBarCoordinator()
    private var pendingMenuAction: (() -> Void)?
    private var mainWindow: NSWindow?
    private var pinnedItems: PinnedStatusItems!
    private var allowsTermination = false
    private var permissionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

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
            AnchorModule(),
            HostsModule(),
            KeepAwakeModule(),
            ShelfModule(),
            MirrorModule(),
            EjectModule(),
            SpeedTestModule(),
            MetalHUDModule()
        ]
    }

    // MARK: NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.verbose = settings.verboseLogging
        MenuBarReveal.restore()   // clear any leftover menu-bar override from a previous crash
        buildMainMenu()
        configureStatusItem()
        settings.syncOnLaunch()
        manager.restoreAll()
        updateStatusButton()
        configurePinnedItems()
        startPermissionTimer()

        // Re-stamp the Quiver menu-bar icon live when its settings change (separate from the permission
        // timer's updateStatusButton(), which deliberately never re-stamps the image).
        let iconChanges = [
            settings.$menuBarIconSymbol.map { _ in () }.eraseToAnyPublisher(),
            settings.$menuBarIconScale.map { _ in () }.eraseToAnyPublisher(),
            settings.$menuBarIconYOffset.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(iconChanges)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshStatusIcon() }
            .store(in: &cancellables)

        // Register the system-wide "Add to Quiver Drop Deck" Service so it appears in any app's right-click
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
        MenuBarReveal.restore()   // safety net: never leave the menu-bar auto-hide setting toggled on quit
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

    /// "Settings" opens the app itself on its General pane (a `nil` module selection), rather than a
    /// separate settings window — so it's the same window you get from "Open Quiver".
    func showSettingsWindow() {
        uiState.selectedModuleID = nil
        showMainWindow()
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

    // MARK: Menu bar

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = currentStatusImage()
        item.button?.imagePosition = .imageOnly
        if let cell = item.button?.cell as? NSButtonCell {
            cell.highlightsBy = [.contentsCellMask, .changeBackgroundCellMask]
        }
        item.button?.toolTip = "Quiver"
        // Clicking the icon toggles a floating Control-Center-style glass panel.
        item.button?.target = self
        item.button?.action = #selector(toggleHubPanel)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        hubPanel.onClose = { [weak self] in
            self?.setStatusIconHighlighted(false)
        }
        menuBarCoordinator.register(
            button: { [weak self] in self?.statusItem?.button },
            open: { [weak self] in self?.openHubPanel() }
        )
    }

    @objc private func toggleHubPanel() {
        if hubPanel.isShown { hubPanel.close() } else { openHubPanel() }
    }

    private func openHubPanel() {
        menuBarCoordinator.closeOpenPanels()    // close the camera / other transient panels
        refreshModulePermissions()
        setStatusIconHighlighted(true)
        hubPanel.show(hubContent(), below: statusItem?.button)
        setStatusIconHighlighted(true)
    }

    /// The hub's SwiftUI content for the floating panel. Actions close the panel first, then run.
    private func hubContent() -> AnyView {
        AnyView(HubGridView(
            manager: manager,
            onOpenModule: { [weak self] id in
                self?.hubPanel.close(); self?.uiState.selectedModuleID = id; self?.showMainWindow()
            },
            onResize: { [weak self] in self?.hubPanel.relayout() },
            inMenu: false
        ))
    }

    /// Creates the per-module menu-bar items for pinned utilities, and keeps them in sync.
    private func configurePinnedItems() {
        pinnedItems = PinnedStatusItems(
            manager: manager,
            openModule: { [weak self] id in self?.uiState.selectedModuleID = id; self?.showMainWindow() },
            openSettings: { [weak self] in self?.showSettingsWindow() },
            coordinator: menuBarCoordinator
        )
        manager.onPinsChanged = { [weak self] in
            Task { @MainActor in self?.pinnedItems?.sync() }
        }
        pinnedItems.sync()

        // Close the camera (Glance Me) whenever one of our menus opens.
        if let mirror = manager.module(id: "mirror") as? MirrorModule {
            menuBarCoordinator.registerPanelCloser { [weak mirror] in mirror?.controller.close() }
        }
    }

    /// Builds the hub's SwiftUI content once. It's reactive (observes the manager/settings), so it
    /// stays current without rebuilding — and the menu is always populated, so the system can hand off
    /// to it in a single click while another menu is open.
    private func buildHubMenu() {
        let hosting = NonVibrantHostingView(rootView: HubGridView(
            manager: manager,
            onOpenModule: { [weak self] id in
                self?.dismissHubMenu { self?.uiState.selectedModuleID = id; self?.showMainWindow() }
            },
            onResize: { [weak self] in self?.repinHubSize() },
            inMenu: true
        ))
        // An NSMenu hosts its content with a vibrant material appearance, which desaturates controls
        // (e.g. an "on" switch renders white instead of accent). Pin the hub to the concrete system
        // appearance so its controls draw with normal colors.
        hosting.appearance = NSApp.effectiveAppearance
        hosting.setFrameSize(hosting.fittingSize)
        hubHosting = hosting
        let item = NSMenuItem()
        item.view = hosting
        hubMenu.removeAllItems()
        hubMenu.addItem(item)
    }

    /// Refreshes permission state and keeps the hosted view sized/appearance-pinned — without
    /// rebuilding it, so the menu is never momentarily empty during a hand-off.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === hubMenu else { return }
        refreshModulePermissions()
        hubHosting?.appearance = NSApp.effectiveAppearance
        if let hosting = hubHosting { hosting.setFrameSize(hosting.fittingSize) }
    }

    /// Re-measure the hosted hub view after its SwiftUI content changes height (Edit mode, resize,
    /// add/remove) so the open NSMenu item grows/shrinks to fit instead of clipping.
    private func repinHubSize() {
        guard let hosting = hubHosting else { return }
        hosting.setFrameSize(hosting.fittingSize)
        hubMenu.items.first?.view = hosting
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === hubMenu else { return }
        menuBarCoordinator.closeOpenPanels()   // close the camera when the hub opens
    }

    /// Runs a hub action (open a window, quit…) after the menu has fully dismissed, so windows open cleanly.
    func menuDidClose(_ menu: NSMenu) {
        guard menu === hubMenu else { return }
        if let action = pendingMenuAction {
            pendingMenuAction = nil
            action()
        } else {
            // No in-menu action chosen — if the cursor is over another of our icons, hand off to it.
            menuBarCoordinator.openItemUnderCursor(excluding: statusItem?.button)
        }
    }

    private func dismissHubMenu(then action: @escaping () -> Void) {
        pendingMenuAction = action
        hubMenu.cancelTracking()
    }

    private func closePopover() {
        hubMenu.cancelTracking()
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

    /// The gem outline (matching the app icon), in an SxS box.
    static func gemOutlinePath(_ S: CGFloat) -> CGPath {
        let cx = S * 0.5
        let path = CGMutablePath()
        path.addLines(between: [
            CGPoint(x: cx - S * 0.20, y: S * 0.72), CGPoint(x: cx + S * 0.20, y: S * 0.72),
            CGPoint(x: cx + S * 0.31, y: S * 0.52), CGPoint(x: cx, y: S * 0.22),
            CGPoint(x: cx - S * 0.31, y: S * 0.52)
        ])
        path.closeSubpath()
        return path
    }

    // The menu-bar glyph: a faceted gem drawn as line-art, as a *template* image — so the system
    // recolours it (white on dark menu bars, black on light) to match the other menu-bar icons, while
    // the facet lines keep it looking like a gem rather than a flat blob. Drawn at `18 * scale`.
    private static func gemStatusImage(scale: CGFloat, yOffset: CGFloat) -> NSImage {
        let pt: CGFloat = 18 * scale
        let gem = NSImage(size: NSSize(width: pt, height: pt), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawMenuGem(in: rect, ctx: ctx)
            return true
        }
        return MenuBarGlyph.offsetTemplate(gem, yOffset: yOffset)
    }

    /// The current Quiver menu-bar image: the user-chosen SF Symbol if set, otherwise the gem — both
    /// sized/offset by the app-icon settings.
    private func currentStatusImage() -> NSImage {
        if let symbol = settings.menuBarIconSymbol,
           let image = MenuBarGlyph.symbolImage(symbol, scale: settings.menuBarIconScale, yOffset: settings.menuBarIconYOffset) {
            return image
        }
        return Self.gemStatusImage(scale: settings.menuBarIconScale, yOffset: settings.menuBarIconYOffset)
    }

    /// A non-template selected-state status image. NSStatusBarButton's normal highlight drawing is tied
    /// to menu tracking/key-window behavior, so the floating nonactivating panel uses an image that
    /// carries the native selected pill with the icon centered inside it.
    private func highlightedStatusImage() -> NSImage {
        let glyphSide = 18 * settings.menuBarIconScale
        let symbolName = settings.menuBarIconSymbol
        let symbolPointSize = 15 * settings.menuBarIconScale
        let yOffset = settings.menuBarIconYOffset
        let width = max(CGFloat(44), glyphSide + 24)
        let height: CGFloat = 26
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor.white.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 13, yRadius: 13).fill()

            let glyphRect = NSRect(
                x: rect.midX - glyphSide / 2,
                y: rect.midY - glyphSide / 2 - yOffset,
                width: glyphSide,
                height: glyphSide
            )
            if let symbol = symbolName,
               let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular)) {
                symbolImage.isTemplate = true
                NSColor.white.set()
                symbolImage.draw(in: glyphRect)
            } else if let ctx = NSGraphicsContext.current?.cgContext {
                Self.drawMenuGem(in: glyphRect, ctx: ctx, color: .white)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func setStatusIconHighlighted(_ highlighted: Bool) {
        guard let item = statusItem else { return }
        if highlighted {
            let image = highlightedStatusImage()
            item.length = max(44, image.size.width)
            item.button?.image = image
            item.button?.highlight(true)
        } else {
            item.length = NSStatusItem.variableLength
            item.button?.image = currentStatusImage()
            item.button?.highlight(false)
        }
    }

    private func refreshStatusIcon() {
        setStatusIconHighlighted(hubPanel.isShown)
    }

    /// The seven gem vertices (A,B,C,D,E,F,G) in an SxS box.
    private static func gemPoints(_ S: CGFloat) -> [CGPoint] {
        let cx = S * 0.5
        return [
            CGPoint(x: cx - S * 0.20, y: S * 0.72), CGPoint(x: cx + S * 0.20, y: S * 0.72),
            CGPoint(x: cx + S * 0.31, y: S * 0.52), CGPoint(x: cx, y: S * 0.22),
            CGPoint(x: cx - S * 0.31, y: S * 0.52),
            CGPoint(x: cx - S * 0.105, y: S * 0.52), CGPoint(x: cx + S * 0.105, y: S * 0.52)
        ]
    }

    private static func drawMenuGem(in rect: CGRect, ctx: CGContext, color: NSColor = .black) {
        let unit: CGFloat = 100
        let bb = gemOutlinePath(unit).boundingBox
        let avail = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        let scale = min(avail.width / bb.width, avail.height / bb.height)
        ctx.saveGState()
        ctx.translateBy(x: avail.midX - bb.midX * scale, y: avail.midY - bb.midY * scale)
        ctx.scaleBy(x: scale, y: scale)
        let p = gemPoints(unit)
        ctx.setStrokeColor(color.cgColor)   // black is ignored for a template; highlighted images pass white.
        ctx.setLineWidth(unit * 0.052)
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        ctx.addPath(gemOutlinePath(unit)); ctx.strokePath()
        // Facet lines: girdle (E–C), crown (A–F, B–G), pavilion (F–D, G–D).
        for s in [[4, 2], [0, 5], [1, 6], [5, 3], [6, 3]] {
            ctx.move(to: p[s[0]]); ctx.addLine(to: p[s[1]])
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

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
        updateActivationPolicy(showDockIcon: false)
    }

    private func updateActivationPolicyForVisibleWindows() {
        let hasVisible = mainWindow?.isVisible == true
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
        if let window = NSApp.keyWindow ?? mainWindow, window.isVisible {
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
