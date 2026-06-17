import SwiftUI

/// Focus-follows-mouse: raises and/or focuses the window under the pointer. Wraps the bridged
/// Objective-C++ `AutoRaiseEngine` (extracted from AutoRaise) and feeds it config from Quiver.
@MainActor
final class AutoRaiseModule: UtilityModule {

    /// How hovering a window behaves. Maps directly onto the engine's raise-delay / focus-delay model.
    enum RaiseMode: String, CaseIterable, Identifiable {
        case raiseOnHover     // raise + focus together
        case focusThenRaise   // focus immediately (no raise), then raise after the delay
        case focusOnly        // focus immediately, never raise

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .raiseOnHover: return "Raise on hover"
            case .focusThenRaise: return "Focus first, then raise"
            case .focusOnly: return "Focus only (never raise)"
            }
        }

        var explanation: String {
            switch self {
            case .raiseOnHover:
                return "Hovering a window brings it to the front and gives it keyboard focus together."
            case .focusThenRaise:
                return "Hovering focuses the window for typing right away (without moving it); it only comes to the front after the delay."
            case .focusOnly:
                return "Hovering focuses the window for typing, but windows never come to the front on their own — classic focus-follows-mouse."
            }
        }

        /// Focus-only and focus-then-raise rely on the experimental focus-first engine support.
        var needsFocusFirst: Bool { self != .raiseOnHover }
    }

    private let engine = AutoRaiseEngine()
    private let pollMillis = 50

    // Persisted configuration.
    private(set) var mode: RaiseMode
    private(set) var raiseDelayMillis: Int   // used by raiseOnHover and focusThenRaise
    private(set) var requireMouseStop: Bool
    private(set) var warpOnSwitch: Bool       // warp pointer to window on cmd-tab / cmd-grave
    private(set) var disableKey: String       // "control" | "option" | "disabled"
    private(set) var ignoreApps: String       // comma-separated app names

    private var lastTrusted: Bool

    /// Raise-delay options (ms). 0 = Instant. Used for "Raise on hover".
    static let raiseDelayChoices: [Int] = [0, 200, 400, 700, 1000]
    /// "Focus first, then raise" needs a real (non-instant) raise delay, otherwise it's identical to raise-on-hover.
    static let focusRaiseDelayChoices: [Int] = [200, 400, 700, 1000]
    static let disableKeyChoices: [String] = ["control", "option", "disabled"]

    init() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "module.autoraise.mode"), let m = RaiseMode(rawValue: raw) {
            mode = m
        } else {
            // Migrate from the earlier "focusFirst" boolean.
            mode = d.bool(forKey: "module.autoraise.focusFirst") ? .focusThenRaise : .raiseOnHover
        }
        raiseDelayMillis = d.object(forKey: "module.autoraise.delayMillis") as? Int ?? 0
        requireMouseStop = d.object(forKey: "module.autoraise.requireMouseStop") as? Bool ?? true
        warpOnSwitch = d.bool(forKey: "module.autoraise.warpOnSwitch")
        disableKey = d.string(forKey: "module.autoraise.disableKey") ?? "control"
        ignoreApps = d.string(forKey: "module.autoraise.ignoreApps") ?? ""
        lastTrusted = AutoRaiseEngine.isAccessibilityTrusted()

        super.init(
            id: "autoraise",
            title: "Follow Focus",
            subtitle: "Raise and/or focus a window just by hovering over it (focus-follows-mouse).",
            symbolName: "macwindow.on.rectangle"
        )

        // If the engine can't do focus-first on this machine, force a safe mode.
        if mode.needsFocusFirst && !focusFirstAvailable { mode = .raiseOnHover }
    }

    var focusFirstAvailable: Bool { AutoRaiseEngine.focusFirstAvailable }
    override var defaultTileSize: TileSize { .wide }

    /// Modes actually selectable on this machine.
    var availableModes: [RaiseMode] {
        focusFirstAvailable ? RaiseMode.allCases : [.raiseOnHover]
    }

    // MARK: Lifecycle

    override func start() {
        lastTrusted = AutoRaiseEngine.isAccessibilityTrusted()
        engine.start(config: buildConfig())
    }

    override func stop() {
        engine.stop()
    }

    private func restartIfRunning() {
        guard isEnabled else { return }
        engine.stop()
        engine.start(config: buildConfig())
    }

    private func ticks(forDelayMillis ms: Int) -> Int {
        ms <= 0 ? 1 : (ms / pollMillis) + 1
    }

    private func buildConfig() -> AutoRaiseConfig {
        let config = AutoRaiseConfig()
        config.pollMillis = pollMillis

        switch (focusFirstAvailable ? mode : .raiseOnHover) {
        case .raiseOnHover:
            config.focusDelay = 0
            config.delay = ticks(forDelayMillis: raiseDelayMillis)   // 1 = instant, n = after (n-1)*poll
        case .focusThenRaise:
            config.focusDelay = 1                                    // focus immediately
            config.delay = ticks(forDelayMillis: max(200, raiseDelayMillis))  // then raise after the delay
        case .focusOnly:
            config.focusDelay = 1                                    // focus immediately
            config.delay = 0                                         // never raise
        }

        config.warpX = 0.5
        config.warpY = 0.5
        config.scale = 2.0
        config.warpEnabled = warpOnSwitch
        config.altTaskSwitcher = false
        config.requireMouseStop = requireMouseStop
        config.ignoreSpaceChanged = false
        config.invertDisableKey = false
        config.invertIgnoreApps = false
        config.ignoreApps = ignoreApps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ignoreApps
        config.ignoreTitles = nil
        config.stayFocusedBundleIds = nil
        config.disableKey = disableKey
        config.mouseDelta = 0
        config.verbose = false
        return config
    }

    // MARK: Configuration setters (restart the engine live when on)

    func setMode(_ value: RaiseMode) {
        mode = value
        // "Focus first, then raise" needs a non-instant raise delay to differ from raise-on-hover.
        if value == .focusThenRaise && raiseDelayMillis < 200 {
            raiseDelayMillis = 200
            UserDefaults.standard.set(200, forKey: defaultsKey("delayMillis"))
        }
        UserDefaults.standard.set(value.rawValue, forKey: defaultsKey("mode"))
        restartIfRunning(); notifyChange()
    }

    func setRaiseDelay(_ ms: Int) {
        raiseDelayMillis = ms
        UserDefaults.standard.set(ms, forKey: defaultsKey("delayMillis"))
        restartIfRunning(); notifyChange()
    }

    func setRequireMouseStop(_ value: Bool) {
        requireMouseStop = value
        UserDefaults.standard.set(value, forKey: defaultsKey("requireMouseStop"))
        restartIfRunning(); notifyChange()
    }

    func setWarpOnSwitch(_ value: Bool) {
        warpOnSwitch = value
        UserDefaults.standard.set(value, forKey: defaultsKey("warpOnSwitch"))
        restartIfRunning(); notifyChange()
    }

    func setDisableKey(_ value: String) {
        disableKey = value
        UserDefaults.standard.set(value, forKey: defaultsKey("disableKey"))
        restartIfRunning(); notifyChange()
    }

    /// Commit the ignore-apps list (call on field submit, not every keystroke).
    func setIgnoreApps(_ value: String) {
        ignoreApps = value
        UserDefaults.standard.set(value, forKey: defaultsKey("ignoreApps"))
        restartIfRunning(); notifyChange()
    }

    // MARK: Permission

    override var permission: PermissionState {
        AutoRaiseEngine.isAccessibilityTrusted()
            ? .ok
            : .needed(reason: "Follow Focus needs Accessibility access to raise and focus windows.",
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
            if trusted { restartIfRunning() }   // (re)start once access is granted
            notifyChange()
        }
    }

    // MARK: Presentation

    override var controlCenterTitle: String { "Focus" }
    override var controlCenterStatusSummary: String {
        guard isEnabled else { return "Off" }
        if !AutoRaiseEngine.isAccessibilityTrusted() { return "Needs access" }
        switch (focusFirstAvailable ? mode : .raiseOnHover) {
        case .raiseOnHover:
            return raiseDelayMillis <= 0 ? "Instant" : "\(raiseDelayMillis) ms"
        case .focusThenRaise:
            return "Focus first"
        case .focusOnly:
            return "Focus only"
        }
    }

    override var statusSummary: String {
        guard isEnabled else { return "Off" }
        var parts: [String] = []
        switch (focusFirstAvailable ? mode : .raiseOnHover) {
        case .raiseOnHover:
            parts.append(raiseDelayMillis <= 0 ? "raise instantly" : "raise after \(raiseDelayMillis)ms")
        case .focusThenRaise:
            parts.append("focus now, raise after \(max(200, raiseDelayMillis))ms")
        case .focusOnly:
            parts.append("focus only")
        }
        if !AutoRaiseEngine.isAccessibilityTrusted() { parts.append("needs access") }
        return "On · " + parts.joined(separator: " · ")
    }

    override func makeQuickControls() -> AnyView? {
        AnyView(AutoRaiseQuickControls(module: self))
    }

    override func makeSettingsView() -> AnyView {
        AnyView(AutoRaiseSettingsView(module: self))
    }

    static func delayLabel(_ ms: Int) -> String {
        ms <= 0 ? "Instant" : "\(ms) ms"
    }
}
