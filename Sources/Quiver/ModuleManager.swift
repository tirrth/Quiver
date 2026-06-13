import Foundation
import Combine

/// Owns the set of utility modules, restores their persisted state at launch, and exposes
/// aggregate information to the shell. Adding a new utility to Quiver means adding one line here.
@MainActor
final class ModuleManager: ObservableObject {
    let modules: [UtilityModule]

    /// Called whenever any module reports a visible state change (used to refresh the menu bar).
    var onAnyStateChange: (() -> Void)?

    init(modules: [UtilityModule]) {
        self.modules = modules
        for module in modules {
            module.onStateChange = { [weak self] in
                self?.objectWillChange.send()
                self?.onAnyStateChange?()
            }
        }
    }

    /// Restore persisted enabled-state and auto-start modules that were on.
    func restoreAll() {
        for module in modules { module.restore() }
    }

    /// Stop every running module (called on full quit).
    func stopAll() {
        for module in modules where module.isEnabled { module.stop() }
    }

    func module(id: String) -> UtilityModule? {
        modules.first { $0.id == id }
    }

    var enabledCount: Int { modules.filter { $0.isEnabled }.count }

    /// True if any enabled module is missing a required permission.
    var hasPendingPermission: Bool {
        modules.contains { $0.isEnabled && !$0.permission.isOK }
    }
}
