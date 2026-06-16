import SwiftUI
import Combine

/// Describes whether a module has the OS-level permission it needs to operate.
enum PermissionState: Equatable {
    /// Everything the module needs is granted.
    case ok
    /// A permission must be granted by the user. `actionTitle` labels the button that resolves it.
    case needed(reason: String, actionTitle: String)
    /// The module cannot run on this machine (e.g. a required private framework is missing).
    case unavailable(reason: String)

    var isOK: Bool { if case .ok = self { return true } else { return false } }
}

/// Base class for every Quiver utility. A module owns its own engine, persists its own
/// configuration, and renders its own controls. The shell only knows about this interface,
/// which is what makes utilities pluggable.
///
/// Subclasses override `start()`/`stop()` (the engine lifecycle) and the presentation hooks.
/// They must NOT toggle `isEnabled` directly — go through `setEnabled(_:)` so persistence and
/// the menu-bar refresh stay in sync.
@MainActor
class UtilityModule: ObservableObject, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    /// SF Symbol shown in the menu and sidebar.
    let symbolName: String

    /// Optical size multiplier for `symbolName`, applied where the icon is drawn. Lets a module nudge
    /// its glyph up or down so it reads at the same visual size as the others (some SF Symbols render
    /// smaller than their point size). Override to adjust; defaults to 1.
    var symbolScale: CGFloat { 1 }

    /// Vertical nudge (in points, at hub-row size; positive = down) for `symbolName`, to optically
    /// centre a glyph that sits high or low in its bounds. Scaled with the icon. Override; defaults to 0.
    var symbolYOffset: CGFloat { 0 }

    // MARK: User-customizable icon (overrides the built-ins above; persisted, set from the icon picker)

    @Published private(set) var customSymbolName: String?
    @Published private(set) var customSymbolScale: CGFloat?
    @Published private(set) var customSymbolYOffset: CGFloat?

    /// The SF Symbol actually drawn — the user's choice if set, otherwise the built-in one.
    var effectiveSymbolName: String { customSymbolName ?? symbolName }

    /// The icon's tuned "designed" size — what the picker's Size slider treats as 100%. A built-in
    /// glyph uses its override (e.g. a glyph that reads small can default to <1); a user-chosen glyph
    /// is neutral (1).
    var iconBaselineScale: CGFloat { customSymbolName == nil ? symbolScale : 1 }

    /// Size/offset actually applied. Size is the baseline times the picker's multiplier (1 = 100%);
    /// offset is the picker's value, or the built-in default for a built-in glyph.
    var effectiveSymbolScale: CGFloat { iconBaselineScale * (customSymbolScale ?? 1) }
    var effectiveSymbolYOffset: CGFloat { customSymbolYOffset ?? (customSymbolName == nil ? symbolYOffset : 0) }

    /// `true` when the user has changed this module's icon from the built-in default.
    var hasCustomIcon: Bool { customSymbolName != nil || customSymbolScale != nil || customSymbolYOffset != nil }

    func setCustomSymbol(_ name: String?) {
        customSymbolName = name
        persist(name, forKey: "icon")
        notifyChange()
    }

    func setCustomSymbolScale(_ scale: CGFloat?) {
        customSymbolScale = scale
        persist(scale.map(Double.init), forKey: "iconScale")
        notifyChange()
    }

    func setCustomSymbolYOffset(_ offset: CGFloat?) {
        customSymbolYOffset = offset
        persist(offset.map(Double.init), forKey: "iconYOffset")
        notifyChange()
    }

    /// Restore the built-in icon (clears all overrides).
    func resetIcon() {
        customSymbolName = nil
        customSymbolScale = nil
        customSymbolYOffset = nil
        persist(nil as String?, forKey: "icon")
        persist(nil as Double?, forKey: "iconScale")
        persist(nil as Double?, forKey: "iconYOffset")
        notifyChange()
    }

    private func persist<T>(_ value: T?, forKey suffix: String) {
        if let value { UserDefaults.standard.set(value, forKey: defaultsKey(suffix)) }
        else { UserDefaults.standard.removeObject(forKey: defaultsKey(suffix)) }
    }

    private func loadCustomIcon() {
        let d = UserDefaults.standard
        customSymbolName = d.string(forKey: defaultsKey("icon"))
        customSymbolScale = (d.object(forKey: defaultsKey("iconScale")) as? Double).map { CGFloat($0) }
        customSymbolYOffset = (d.object(forKey: defaultsKey("iconYOffset")) as? Double).map { CGFloat($0) }
    }

    /// `true` for background utilities with an on/off engine (Follow Focus, Keep Awake). `false` for
    /// "tool" utilities you simply open and use (Hosts), which show an Open affordance instead of a
    /// switch and surface their controls without an enabled gate.
    let isToggleable: Bool

    /// The Control-Center tile size this module looks best at by default (rich modules can prefer a
    /// larger tile). Override to change; users can still resize. Defaults to small (1×1).
    var defaultTileSize: TileSize { .small }

    /// Set by `ModuleManager`. Invoke (via `notifyChange()`) whenever user-visible state changes
    /// so the menu-bar status item and popover refresh.
    var onStateChange: (() -> Void)?

    /// Set by `ModuleManager`. Route a user-facing error to the shell (shows an alert).
    var errorReporter: ((String) -> Void)?

    @Published private(set) var isEnabled = false

    init(id: String, title: String, subtitle: String, symbolName: String, isToggleable: Bool = true) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.isToggleable = isToggleable
        loadCustomIcon()
    }

    // MARK: Lifecycle — override these

    /// Start the underlying engine. Must be safe to call only when not already running.
    func start() {}

    /// Stop the underlying engine. Must be idempotent and fully tear down resources so the
    /// module can be started again cleanly.
    func stop() {}

    // MARK: Enable / disable (do not override)

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            Log.info("Enabling module \(id)")
            start()
        } else {
            Log.info("Disabling module \(id)")
            stop()
        }
        UserDefaults.standard.set(enabled, forKey: defaultsKey("enabled"))
        notifyChange()
    }

    /// Restore the persisted enabled-state at launch, starting the engine if it was on.
    func restore() {
        if UserDefaults.standard.bool(forKey: defaultsKey("enabled")) {
            isEnabled = true
            Log.info("Restoring enabled module \(id)")
            start()
        }
        notifyChange()
    }

    /// Push a change notification to SwiftUI and the shell.
    func notifyChange() {
        objectWillChange.send()
        onStateChange?()
    }

    /// Surface a user-facing error (e.g. a cancelled admin prompt) through the shell.
    func reportError(_ message: String) {
        errorReporter?(message)
    }

    /// Called periodically by the shell (≈ every 2s). Override to re-check OS permissions or
    /// external state (e.g. Follow Focus watching for Accessibility to be granted).
    func periodicRefresh() {}

    // MARK: Persistence helpers

    /// Namespaced UserDefaults key, e.g. `module.keepawake.duration`.
    func defaultsKey(_ suffix: String) -> String { "module.\(id).\(suffix)" }

    // MARK: Presentation — override as needed

    /// One-line status shown in the menu (e.g. "On · delay 0ms").
    var statusSummary: String { isEnabled ? "On" : "Off" }

    /// A live text label to show next to this module's pinned menu-bar icon (e.g. a network speed
    /// readout). `nil` (the default) means icon-only. Refreshed whenever the module reports a change.
    var menuBarTitle: String? { nil }

    /// Permission needed for the module to actually work.
    var permission: PermissionState { .ok }

    /// Resolve `permission` (open System Settings, install a helper, …).
    func requestPermission() {}

    /// Compact controls embedded inline in the menu-bar popover. Return nil for none.
    func makeQuickControls() -> AnyView? { nil }

    /// Full settings pane shown in the main window's detail area.
    func makeSettingsView() -> AnyView { AnyView(EmptyView()) }

    // MARK: Pinned menu-bar item

    /// Whether a left-click on this module's pinned menu-bar icon performs a direct action instead of
    /// opening its options menu. Override together with `menuBarActivate()`.
    var menuBarActivatesDirectly: Bool { false }

    /// The direct left-click action for a pinned menu-bar icon, given the icon's screen `rect`
    /// (e.g. open the camera just below it).
    func menuBarActivate(near rect: CGRect) {}
}
