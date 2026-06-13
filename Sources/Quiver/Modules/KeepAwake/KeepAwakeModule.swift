import Foundation
import IOKit.pwr_mgt
import SwiftUI

/// Prevents the Mac from going to sleep while enabled, using an IOKit power-management assertion.
/// Optionally keeps the display awake too, and can auto-expire after a chosen duration.
@MainActor
final class KeepAwakeModule: UtilityModule {
    /// 0 means "indefinite".
    private(set) var durationMinutes: Int
    private(set) var keepDisplayAwake: Bool
    private(set) var expiresAt: Date?

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var expiryTimer: Timer?

    static let durationChoices: [Int] = [0, 30, 60, 120, 240]

    init() {
        let defaults = UserDefaults.standard
        durationMinutes = defaults.integer(forKey: "module.keepawake.duration")
        keepDisplayAwake = defaults.bool(forKey: "module.keepawake.display")
        super.init(
            id: "keepawake",
            title: "Keep Awake",
            subtitle: "Stop your Mac from sleeping while this is on — handy for downloads, presentations, or long builds.",
            symbolName: "cup.and.saucer"
        )
    }

    // MARK: Lifecycle

    override func start() {
        createAssertion()
        scheduleExpiry()
    }

    override func stop() {
        releaseAssertion()
        expiryTimer?.invalidate()
        expiryTimer = nil
        expiresAt = nil
    }

    // MARK: Configuration

    func setDuration(_ minutes: Int) {
        durationMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: defaultsKey("duration"))
        if isEnabled { scheduleExpiry() }
        notifyChange()
    }

    func setKeepDisplayAwake(_ enabled: Bool) {
        keepDisplayAwake = enabled
        UserDefaults.standard.set(enabled, forKey: defaultsKey("display"))
        if isEnabled { recreateAssertion() }
        notifyChange()
    }

    // MARK: Assertion management

    private func createAssertion() {
        guard !hasAssertion else { return }
        let type = keepDisplayAwake
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Quiver Keep Awake" as CFString,
            &assertionID
        )
        hasAssertion = (result == kIOReturnSuccess)
        if !hasAssertion {
            Log.error("KeepAwake: failed to create power assertion (\(result))")
        }
    }

    private func releaseAssertion() {
        guard hasAssertion else { return }
        IOPMAssertionRelease(assertionID)
        hasAssertion = false
        assertionID = 0
    }

    private func recreateAssertion() {
        releaseAssertion()
        createAssertion()
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard durationMinutes > 0 else {
            expiresAt = nil
            return
        }
        let interval = TimeInterval(durationMinutes * 60)
        expiresAt = Date().addingTimeInterval(interval)
        expiryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.setEnabled(false) }
        }
    }

    // MARK: Presentation

    override var statusSummary: String {
        guard isEnabled else { return "Off" }
        var parts = ["On"]
        if let expiresAt {
            parts.append("until \(Self.timeFormatter.string(from: expiresAt))")
        } else {
            parts.append("indefinite")
        }
        if keepDisplayAwake { parts.append("display on") }
        return parts.joined(separator: " · ")
    }

    override func makeQuickControls() -> AnyView? {
        AnyView(KeepAwakeQuickControls(module: self))
    }

    override func makeSettingsView() -> AnyView {
        AnyView(KeepAwakeSettingsView(module: self))
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static func durationLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Indefinitely"
        case 60: return "1 hour"
        case 120: return "2 hours"
        case 240: return "4 hours"
        default:
            if minutes % 60 == 0 { return "\(minutes / 60) hours" }
            return "\(minutes) min"
        }
    }
}
