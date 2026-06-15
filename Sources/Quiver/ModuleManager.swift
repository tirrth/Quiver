import Foundation
import Combine

/// Owns the set of utility modules, restores their persisted state at launch, and exposes
/// aggregate information to the shell. Adding a new utility to Quiver means adding one line here.
@MainActor
final class ModuleManager: ObservableObject {
    let modules: [UtilityModule]

    /// Persisted display order (module ids) and the set of modules hidden from the menu-bar hub.
    @Published private(set) var order: [String] = []
    @Published private(set) var hiddenIDs: Set<String> = []
    @Published private(set) var pinnedIDs: Set<String> = []
    private static let orderKey = "modules.order"
    private static let hiddenKey = "modules.hidden"
    private static let pinnedKey = "modules.pinned"

    /// Called when the set of pinned (menu-bar) modules changes, so the shell can add/remove items.
    var onPinsChanged: (() -> Void)?

    /// Called whenever any module reports a visible state change (used to refresh the menu bar).
    var onAnyStateChange: (() -> Void)?

    /// Called when a module reports a user-facing error (used to present an alert).
    var onError: ((String) -> Void)?

    init(modules: [UtilityModule]) {
        self.modules = modules
        // Restore display order (keeping only ids that still exist, then appending any new modules).
        var ord = (UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []).filter { id in modules.contains { $0.id == id } }
        for m in modules where !ord.contains(m.id) { ord.append(m.id) }
        self.order = ord
        self.hiddenIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
        self.pinnedIDs = Set(UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? [])
        for module in modules {
            module.onStateChange = { [weak self] in
                self?.objectWillChange.send()
                self?.onAnyStateChange?()
            }
            module.errorReporter = { [weak self] message in
                self?.onError?(message)
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

    // MARK: Order & menu visibility

    /// All modules in the user's chosen order (used by the main window).
    var orderedModules: [UtilityModule] {
        let byID = Dictionary(modules.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return order.compactMap { byID[$0] }
    }

    /// Modules that are shown in the menu-bar hub, in order.
    var menuModules: [UtilityModule] { orderedModules.filter { !hiddenIDs.contains($0.id) } }

    func isHidden(_ id: String) -> Bool { hiddenIDs.contains(id) }

    func setHidden(_ id: String, _ hidden: Bool) {
        if hidden { hiddenIDs.insert(id) } else { hiddenIDs.remove(id) }
        UserDefaults.standard.set(Array(hiddenIDs), forKey: Self.hiddenKey)
        onAnyStateChange?()
    }

    func isPinned(_ id: String) -> Bool { pinnedIDs.contains(id) }

    /// Pin/unpin a module to its own menu-bar item.
    func setPinned(_ id: String, _ pinned: Bool) {
        if pinned { pinnedIDs.insert(id) } else { pinnedIDs.remove(id) }
        UserDefaults.standard.set(Array(pinnedIDs), forKey: Self.pinnedKey)
        onPinsChanged?()
    }

    /// Reorder for a SwiftUI List `.onMove`.
    func moveModules(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        UserDefaults.standard.set(order, forKey: Self.orderKey)
    }

    /// Move `id` to sit just before `targetID` (used by drag-and-drop reordering of the tiles).
    func move(_ id: String, before targetID: String) {
        guard id != targetID, let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        let to = order.firstIndex(of: targetID) ?? order.count
        order.insert(id, at: to)
        UserDefaults.standard.set(order, forKey: Self.orderKey)
    }
}
