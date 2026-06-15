import AppKit
import SwiftUI

/// A per-action shortcut override: explicitly unbound, or a custom combo. Absence means "use default".
private enum ShortcutOverride { case cleared; case custom(Shortcut) }

/// Snap To: arrange the frontmost window to halves, quarters, maximize, or centre — via global keyboard
/// shortcuts or the buttons in its settings pane. Reuses the Accessibility permission shared with
/// Follow Focus. Toggling the module on/off enables/disables the global shortcuts.
@MainActor
final class AnchorModule: UtilityModule {
    let engine = AnchorEngine()
    private let hotKeys = HotKeyCenter()

    /// The last non-Quiver app the user activated. Buttons in Quiver's own window arrange *this*
    /// window (since Quiver is frontmost while you click), while global shortcuts use the front app.
    private var lastActiveApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    private var lastTrusted: Bool
    private(set) var gap: Int
    private(set) var dragSnapEnabled: Bool
    private(set) var doubleClickFullScreen: Bool
    private var overrides: [WindowAction: ShortcutOverride] = [:]
    private lazy var dragController = DragSnapController(
        engine: engine,
        gap: { [weak self] in CGFloat(self?.gap ?? 0) },
        topEdgeFullScreen: { [weak self] in !(self?.doubleClickFullScreen ?? false) }
    )
    private lazy var doubleClickController = DoubleClickController(engine: engine)

    static let gapChoices: [Int] = [0, 4, 8, 12, 16, 24]

    init() {
        let d = UserDefaults.standard
        gap = d.object(forKey: "module.anchor.gap") as? Int ?? 0
        dragSnapEnabled = d.object(forKey: "module.anchor.dragSnap") as? Bool ?? true
        doubleClickFullScreen = d.object(forKey: "module.anchor.doubleClickFullScreen") as? Bool ?? false
        lastTrusted = AutoRaiseEngine.isAccessibilityTrusted()
        super.init(
            id: "anchor",
            title: "Snap To",
            subtitle: "Snap the front window to halves, quarters, maximize, or centre — by click or keyboard shortcut.",
            symbolName: "rectangle.split.2x2"
        )
        observeActivation()
        loadShortcutOverrides()
    }

    deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    private func observeActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.lastActiveApp = app }
        }
    }

    // MARK: Lifecycle

    override func start() {
        lastTrusted = AutoRaiseEngine.isAccessibilityTrusted()
        registerHotKeys()
        if dragSnapEnabled { dragController.start() }
        if doubleClickFullScreen { doubleClickController.start() }
    }

    override func stop() {
        hotKeys.unregisterAll()
        dragController.stop()
        doubleClickController.stop()
    }

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        for action in WindowAction.allCases {
            guard let s = effectiveShortcut(for: action) else { continue }
            hotKeys.register(keyCode: s.keyCode, modifiers: s.modifiers) { [weak self] in
                MainActor.assumeIsolated { self?.perform(action) }
            }
        }
    }

    /// The window to arrange: the front app, unless that's Quiver itself (e.g. you clicked a button
    /// in Quiver's window), in which case the last app you were actually using.
    private func targetApp() -> NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier { return front }
        return lastActiveApp
    }

    /// Run an action now (shared by the global shortcuts and the settings buttons).
    func perform(_ action: WindowAction) {
        engine.arrange(action, gap: CGFloat(gap), app: targetApp())
    }

    func setGap(_ value: Int) {
        gap = value
        UserDefaults.standard.set(value, forKey: defaultsKey("gap"))
        notifyChange()
    }

    func setDragSnap(_ value: Bool) {
        dragSnapEnabled = value
        UserDefaults.standard.set(value, forKey: defaultsKey("dragSnap"))
        if isEnabled { value ? dragController.start() : dragController.stop() }
        notifyChange()
    }

    func setDoubleClickFullScreen(_ value: Bool) {
        doubleClickFullScreen = value
        UserDefaults.standard.set(value, forKey: defaultsKey("doubleClickFullScreen"))
        if isEnabled { value ? doubleClickController.start() : doubleClickController.stop() }
        notifyChange()
    }

    // MARK: Shortcut overrides

    func effectiveShortcut(for action: WindowAction) -> Shortcut? {
        switch overrides[action] {
        case .some(.cleared): return nil
        case .some(.custom(let s)): return s
        case .none: return action.defaultShortcut
        }
    }

    func isOverridden(_ action: WindowAction) -> Bool { overrides[action] != nil }

    /// Assign a custom shortcut. Returns the conflicting action if the combo is already in use.
    @discardableResult
    func setShortcut(_ action: WindowAction, _ shortcut: Shortcut) -> WindowAction? {
        if let other = WindowAction.allCases.first(where: { $0 != action && effectiveShortcut(for: $0) == shortcut }) {
            return other
        }
        overrides[action] = .custom(shortcut)
        persistOverride(action)
        if isEnabled { registerHotKeys() }
        notifyChange()
        return nil
    }

    func clearShortcut(_ action: WindowAction) {
        overrides[action] = .cleared
        persistOverride(action)
        if isEnabled { registerHotKeys() }
        notifyChange()
    }

    func resetShortcut(_ action: WindowAction) {
        overrides[action] = nil
        persistOverride(action)
        if isEnabled { registerHotKeys() }
        notifyChange()
    }

    func resetAllShortcuts() {
        for action in WindowAction.allCases { overrides[action] = nil; persistOverride(action) }
        if isEnabled { registerHotKeys() }
        notifyChange()
    }

    private func persistOverride(_ action: WindowAction) {
        let key = defaultsKey("shortcut.\(action.rawValue)")
        switch overrides[action] {
        case .some(.cleared): UserDefaults.standard.set("cleared", forKey: key)
        case .some(.custom(let s)): UserDefaults.standard.set(s.storageString, forKey: key)
        case .none: UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func loadShortcutOverrides() {
        for action in WindowAction.allCases {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey("shortcut.\(action.rawValue)")) else { continue }
            if raw == "cleared" { overrides[action] = .cleared }
            else if let s = Shortcut(storage: raw) { overrides[action] = .custom(s) }
        }
    }

    // MARK: Permission (shared with Follow Focus)

    override var permission: PermissionState {
        AutoRaiseEngine.isAccessibilityTrusted()
            ? .ok
            : .needed(reason: "Snap To needs Accessibility access to move and resize windows.",
                      actionTitle: "Grant Access")
    }

    override func requestPermission() {
        _ = AutoRaiseEngine.promptAccessibility()
        AutoRaiseEngine.openAccessibilitySettings()
    }

    override func periodicRefresh() {
        let trusted = AutoRaiseEngine.isAccessibilityTrusted()
        if trusted != lastTrusted {
            lastTrusted = trusted
            notifyChange()
        }
    }

    // MARK: Presentation

    override var statusSummary: String {
        guard isEnabled else { return "Off" }
        if !AutoRaiseEngine.isAccessibilityTrusted() { return "On · needs access" }
        return gap > 0 ? "On · \(gap)px gap" : "On · shortcuts active"
    }

    override func makeQuickControls() -> AnyView? {
        AnyView(AnchorQuickControls(module: self))
    }

    override func makeSettingsView() -> AnyView {
        AnyView(AnchorSettingsView(module: self))
    }
}
