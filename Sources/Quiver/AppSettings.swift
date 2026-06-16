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

    // The Quiver app's own menu-bar icon. `menuBarIconSymbol == nil` means the built-in gem; a value
    // means a user-chosen SF Symbol. Scale/offset apply to whichever is shown (so the gem is resizable).
    @Published private(set) var menuBarIconSymbol: String?
    @Published private(set) var menuBarIconScale: CGFloat
    @Published private(set) var menuBarIconYOffset: CGFloat

    /// Surfaces errors to the shell so it can present an alert.
    var errorHandler: ((String) -> Void)?

    private let defaults = UserDefaults.standard

    init() {
        // Derive launchAtLogin from the actual installed agent so the toggle can't drift.
        launchAtLogin = LoginItem.isInstalled
        startHiddenAtLogin = defaults.object(forKey: Keys.startHidden) as? Bool ?? true
        verboseLogging = defaults.bool(forKey: Keys.verboseLogging)
        menuBarIconSymbol = defaults.string(forKey: Keys.menuBarIconSymbol)
        menuBarIconScale = (defaults.object(forKey: Keys.menuBarIconScale) as? Double).map { CGFloat($0) } ?? 1
        menuBarIconYOffset = (defaults.object(forKey: Keys.menuBarIconYOffset) as? Double).map { CGFloat($0) } ?? 0
    }

    func setMenuBarIconSymbol(_ name: String?) {
        menuBarIconSymbol = name
        if let name { defaults.set(name, forKey: Keys.menuBarIconSymbol) }
        else { defaults.removeObject(forKey: Keys.menuBarIconSymbol) }
    }

    func setMenuBarIconScale(_ scale: CGFloat) {
        menuBarIconScale = scale
        defaults.set(Double(scale), forKey: Keys.menuBarIconScale)
    }

    func setMenuBarIconYOffset(_ offset: CGFloat) {
        menuBarIconYOffset = offset
        defaults.set(Double(offset), forKey: Keys.menuBarIconYOffset)
    }

    /// Restore the built-in gem at its default size.
    func resetMenuBarIcon() {
        setMenuBarIconSymbol(nil)
        setMenuBarIconScale(1)
        setMenuBarIconYOffset(0)
    }

    var hasCustomMenuBarIcon: Bool { menuBarIconSymbol != nil || menuBarIconScale != 1 || menuBarIconYOffset != 0 }

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
        static let menuBarIconSymbol = "app.menuBarIcon.symbol"
        static let menuBarIconScale = "app.menuBarIcon.scale"
        static let menuBarIconYOffset = "app.menuBarIcon.yOffset"
    }
}
