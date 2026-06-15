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

    /// `true` for background utilities with an on/off engine (Follow Focus, Keep Awake). `false` for
    /// "tool" utilities you simply open and use (Hosts), which show an Open affordance instead of a
    /// switch and surface their controls without an enabled gate.
    let isToggleable: Bool

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
