import SwiftUI

/// Focus-follows-mouse: raises and focuses the window under the pointer. Wraps the bridged
/// Objective-C++ `AutoRaiseEngine` (extracted from AutoRaise) and feeds it config from Quiver.
@MainActor
final class AutoRaiseModule: UtilityModule {
    private let engine = AutoRaiseEngine()
    private let pollMillis = 50

    // Persisted configuration.
    private(set) var delayMillis: Int       // 0 = raise instantly on hover
    private(set) var focusFirst: Bool       // focus before raising (experimental)
    private(set) var requireMouseStop: Bool
    private(set) var warpOnSwitch: Bool      // warp pointer to window on cmd-tab / cmd-grave
    private(set) var disableKey: String      // "control" | "option" | "disabled"
    private(set) var ignoreApps: String      // comma-separated app names

    private var lastTrusted: Bool

    static let delayChoices: [Int] = [0, 200, 400, 700, 1000]
    static let disableKeyChoices: [String] = ["control", "option", "disabled"]

    init() {
        let d = UserDefaults.standard
        delayMillis = d.object(forKey: "module.autoraise.delayMillis") as? Int ?? 0
        focusFirst = d.bool(forKey: "module.autoraise.focusFirst")
        requireMouseStop = d.object(forKey: "module.autoraise.requireMouseStop") as? Bool ?? true
        warpOnSwitch = d.bool(forKey: "module.autoraise.warpOnSwitch")
        disableKey = d.string(forKey: "module.autoraise.disableKey") ?? "control"
        ignoreApps = d.string(forKey: "module.autoraise.ignoreApps") ?? ""
        lastTrusted = AutoRaiseEngine.isAccessibilityTrusted()

        super.init(
            id: "autoraise",
            title: "AutoRaise",
            subtitle: "Raise and focus a window just by hovering over it (focus-follows-mouse).",
            symbolName: "macwindow.on.rectangle"
        )
    }

    var focusFirstAvailable: Bool { AutoRaiseEngine.focusFirstAvailable }

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

    private func buildConfig() -> AutoRaiseConfig {
        let config = AutoRaiseConfig()
        config.pollMillis = pollMillis
        config.delay = delayMillis <= 0 ? 1 : (delayMillis / pollMillis) + 1
        config.focusDelay = (focusFirst && focusFirstAvailable) ? 1 : 0
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

    func setDelayMillis(_ value: Int) {
        delayMillis = value
        UserDefaults.standard.set(value, forKey: defaultsKey("delayMillis"))
        restartIfRunning(); notifyChange()
    }

    func setFocusFirst(_ value: Bool) {
        focusFirst = value
        UserDefaults.standard.set(value, forKey: defaultsKey("focusFirst"))
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
            : .needed(reason: "AutoRaise needs Accessibility access to raise and focus windows.",
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
            // Once the user grants access, (re)start so the event tap/AX hooks take effect.
            if trusted { restartIfRunning() }
            notifyChange()
        }
    }

    // MARK: Presentation

    override var statusSummary: String {
        guard isEnabled else { return "Off" }
        var parts = ["On"]
        parts.append(delayMillis <= 0 ? "instant" : "\(delayMillis)ms delay")
        if focusFirst && focusFirstAvailable { parts.append("focus-first") }
        if !AutoRaiseEngine.isAccessibilityTrusted() { parts.append("needs access") }
        return parts.joined(separator: " · ")
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
