import AppKit
import SwiftUI
import Combine

/// Builds a template menu-bar glyph from an SF Symbol at a continuous size scale and vertical offset.
/// Shared by the pinned-module icons and the Quiver app icon so both honour the icon picker's controls.
enum MenuBarGlyph {
    /// `scale` multiplies a base menu-bar point size; `yOffset` shifts the glyph (positive = down) by
    /// padding the image (the status bar centres it). Returns nil only if the symbol doesn't exist.
    static func symbolImage(_ name: String, scale: CGFloat, yOffset: CGFloat) -> NSImage? {
        var base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        if scale != 1 {
            base = base?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15 * scale, weight: .regular)) ?? base
        }
        guard let symbol = base else { return nil }
        return offsetTemplate(symbol, yOffset: yOffset)
    }

    /// Wraps an image as a template, padding one edge so the status bar's centring nudges it up/down.
    static func offsetTemplate(_ image: NSImage, yOffset: CGFloat) -> NSImage {
        guard yOffset != 0 else { image.isTemplate = true; return image }
        let size = image.size
        let pad = abs(yOffset)
        let glyphY: CGFloat = yOffset > 0 ? 0 : pad   // NSImage is y-up: y=0 is the bottom edge
        let out = NSImage(size: NSSize(width: size.width, height: size.height + pad), flipped: false) { _ in
            image.draw(in: NSRect(x: 0, y: glyphY, width: size.width, height: size.height))
            return true
        }
        out.isTemplate = true
        return out
    }
}

/// One-click hand-off between Quiver's own menu-bar icons. macOS does this automatically for standard
/// menus, but not for status items whose menus host a custom SwiftUI view — so when one of our menus
/// closes, if the cursor is over another of our icons, we open that one ourselves.
@MainActor
final class MenuBarCoordinator {
    private struct Entry { let button: () -> NSStatusBarButton?; let open: () -> Void }
    private var entries: [Entry] = []

    func register(button: @escaping () -> NSStatusBarButton?, open: @escaping () -> Void) {
        entries.append(Entry(button: button, open: open))
    }

    private var panelClosers: [() -> Void] = []

    /// Register a transient panel (e.g. the camera) to be closed when any of our menus opens.
    func registerPanelCloser(_ close: @escaping () -> Void) { panelClosers.append(close) }

    /// Close registered transient panels — called as one of our menus is about to open.
    func closeOpenPanels() { panelClosers.forEach { $0() } }

    /// Called from a menu's `menuDidClose`: if the cursor sits over a *different* one of our icons,
    /// open it (deferred a tick so the just-closed menu has fully torn down first).
    func openItemUnderCursor(excluding closing: NSStatusBarButton?) {
        let location = NSEvent.mouseLocation
        for entry in entries {
            guard let button = entry.button(), button !== closing,
                  let frame = button.window?.frame, frame.contains(location) else { continue }
            let open = entry.open
            DispatchQueue.main.async { open() }
            return
        }
    }
}

/// Manages a dedicated menu-bar status item for each "pinned" utility. Driven by `ModuleManager`'s
/// pinned set: `sync()` adds an item for each newly-pinned module and removes items for unpinned ones.
@MainActor
final class PinnedStatusItems {
    private let manager: ModuleManager
    private let openModule: (String) -> Void
    private let openSettings: () -> Void
    private let coordinator: MenuBarCoordinator
    private var handlers: [String: PinnedItemHandler] = [:]

    init(manager: ModuleManager,
         openModule: @escaping (String) -> Void,
         openSettings: @escaping () -> Void,
         coordinator: MenuBarCoordinator) {
        self.manager = manager
        self.openModule = openModule
        self.openSettings = openSettings
        self.coordinator = coordinator
    }

    func sync() {
        let pinned = manager.pinnedIDs
        for (id, handler) in handlers where !pinned.contains(id) {
            handler.dispose()
            handlers[id] = nil
        }
        for id in pinned where handlers[id] == nil {
            guard let module = manager.module(id: id) else { continue }
            handlers[id] = PinnedItemHandler(module: module, manager: manager,
                                             openModule: openModule, openSettings: openSettings,
                                             coordinator: coordinator)
        }
    }
}

/// Owns one NSStatusItem for a pinned module. Modules that show controls use a permanently-assigned
/// `statusItem.menu`, built lazily through `NSMenuDelegate` — so the system manages menu-bar tracking
/// and hands off to another item in a single click (native behaviour). Direct-action modules (the
/// camera) use a button action instead.
@MainActor
final class PinnedItemHandler: NSObject, NSMenuDelegate {
    private let moduleId: String
    private let manager: ModuleManager
    private let openModule: (String) -> Void
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private let coordinator: MenuBarCoordinator
    private let controlsMenu = NSMenu()
    private var controlsHosting: NSView?
    private var pendingAction: (() -> Void)?
    private var iconCancellable: AnyCancellable?

    init(module: UtilityModule, manager: ModuleManager,
         openModule: @escaping (String) -> Void,
         openSettings: @escaping () -> Void,
         coordinator: MenuBarCoordinator) {
        self.moduleId = module.id
        self.manager = manager
        self.openModule = openModule
        self.openSettings = openSettings
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = Self.menuBarImage(for: module)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = module.title

        // Re-stamp the menu-bar icon live when the module's icon (or any state) changes.
        iconCancellable = module.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refreshIcon() }
        }

        if module.menuBarActivatesDirectly {
            // e.g. Glance Me opens the camera — a button action, not a menu.
            statusItem.button?.target = self
            statusItem.button?.action = #selector(clicked(_:))
            statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else {
            // Permanent menu, populated now (not lazily) so the system can hand off to it instantly.
            controlsMenu.delegate = self
            buildControlsMenu(module)
            statusItem.menu = controlsMenu
        }

        coordinator.register(
            button: { [weak self] in self?.statusItem.button },
            open: { [weak self] in self?.statusItem.button?.performClick(nil) }
        )
    }

    func dispose() {
        controlsMenu.cancelTracking()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// The menu-bar glyph for a pinned module, honouring its effective icon (the user's chosen glyph
    /// or the built-in default) and the picker's size/offset.
    private static func menuBarImage(for module: UtilityModule) -> NSImage? {
        MenuBarGlyph.symbolImage(module.effectiveSymbolName,
                                 scale: module.effectiveSymbolScale,
                                 yOffset: module.effectiveSymbolYOffset)
    }

    private func refreshIcon() {
        guard let module else { return }
        statusItem.button?.image = Self.menuBarImage(for: module)
        statusItem.button?.toolTip = module.title
    }

    private var module: UtilityModule? { manager.module(id: moduleId) }

    // MARK: Direct-action modules (the camera)

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let module else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            present(manageMenu(), from: sender)
        } else {
            module.menuBarActivate(near: iconRect)   // e.g. Glance Me opens the camera below the icon
        }
    }

    private var iconRect: CGRect {
        guard let button = statusItem.button, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func present(_ menu: NSMenu, from button: NSStatusBarButton) {
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func manageMenu() -> NSMenu {
        let menu = NSMenu()
        addItem(to: menu, "Open in Quiver…", #selector(openInQuiver))
        addItem(to: menu, "Settings…", #selector(openSettingsAction))
        menu.addItem(.separator())
        addItem(to: menu, "Remove from Menu Bar", #selector(removeFromMenuBar))
        return menu
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func openInQuiver() { openModule(moduleId) }
    @objc private func openSettingsAction() { openSettings() }
    @objc private func removeFromMenuBar() { manager.setPinned(moduleId, false) }

    // MARK: Controls menu (built lazily so the system owns the tracking)

    private func buildControlsMenu(_ module: UtilityModule) {
        let id = moduleId
        let view = PinnedControlsView(
            module: module,
            onOpenInQuiver: { [weak self] in self?.deferAction { [weak self] in self?.openModule(id) } },
            onRemove: { [weak self] in self?.deferAction { [weak self] in self?.manager.setPinned(id, false) } }
        )
        let hosting = NonVibrantHostingView(rootView: view)
        hosting.appearance = NSApp.effectiveAppearance
        hosting.setFrameSize(hosting.fittingSize)
        controlsHosting = hosting
        let item = NSMenuItem()
        item.view = hosting
        controlsMenu.removeAllItems()
        controlsMenu.addItem(item)
    }

    /// Keeps the (already-built) hosted view sized and appearance-pinned, without rebuilding it — so
    /// the menu is never momentarily empty during a hand-off from another open menu.
    func menuNeedsUpdate(_ menu: NSMenu) {
        controlsHosting?.appearance = NSApp.effectiveAppearance
        if let hosting = controlsHosting { hosting.setFrameSize(hosting.fittingSize) }
    }

    func menuWillOpen(_ menu: NSMenu) {
        coordinator.closeOpenPanels()   // e.g. close the camera when a menu opens
    }

    func menuDidClose(_ menu: NSMenu) {
        if let action = pendingAction {
            pendingAction = nil
            action()
        } else {
            // No in-menu action was chosen — if the cursor is now over another of our icons, hand off.
            coordinator.openItemUnderCursor(excluding: statusItem.button)
        }
    }

    /// Closes the controls menu, then runs `action` once it has fully dismissed.
    private func deferAction(_ action: @escaping () -> Void) {
        pendingAction = action
        controlsMenu.cancelTracking()
    }
}
