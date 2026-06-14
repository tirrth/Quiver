import Foundation
import Combine

/// App-wide preferences (distinct from per-module config): launch at login, start hidden,
/// and verbose logging. The settings store for the app shell.
@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var startHiddenAtLogin: Bool
    @Published var verboseLogging: Bool {
        didSet {
            defaults.set(verboseLogging, forKey: Keys.verboseLogging)
            Log.verbose = verboseLogging
        }
    }

    /// Surfaces errors to the shell so it can present an alert.
    var errorHandler: ((String) -> Void)?

    private let defaults = UserDefaults.standard

    init() {
        // Derive launchAtLogin from the actual installed agent so the toggle can't drift.
        launchAtLogin = LoginItem.isInstalled
        startHiddenAtLogin = defaults.object(forKey: Keys.startHidden) as? Bool ?? true
        verboseLogging = defaults.bool(forKey: Keys.verboseLogging)
    }

    /// Re-point the launch agent at the current executable path on every launch (handles the
    /// app being moved/reinstalled).
    func syncOnLaunch() {
        guard launchAtLogin else { return }
        do {
            try LoginItem.sync(enabled: true, launchHidden: startHiddenAtLogin)
        } catch {
            Log.error("Failed to sync login item: \(error.localizedDescription)")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let previous = launchAtLogin
        launchAtLogin = enabled
        do {
            try LoginItem.sync(enabled: enabled, launchHidden: startHiddenAtLogin)
        } catch {
            launchAtLogin = previous
            errorHandler?(error.localizedDescription)
        }
    }

    func setStartHidden(_ hidden: Bool) {
        let previous = startHiddenAtLogin
        startHiddenAtLogin = hidden
        defaults.set(hidden, forKey: Keys.startHidden)
        guard launchAtLogin else { return }
        do {
            try LoginItem.sync(enabled: true, launchHidden: hidden)
        } catch {
            startHiddenAtLogin = previous
            defaults.set(previous, forKey: Keys.startHidden)
            errorHandler?(error.localizedDescription)
        }
    }

    private enum Keys {
        static let startHidden = "app.startHiddenAtLogin"
        static let verboseLogging = "app.verboseLogging"
    }
}
