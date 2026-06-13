import Foundation
import Combine

/// Observable state for the Hosts editor. Ported from HostsMachine. Loads /etc/hosts, applies
/// privileged changes, and refreshes on success.
@MainActor
final class HostsViewModel: ObservableObject {
    @Published private(set) var rules: [HostRule] = []
    @Published private(set) var activeCount = 0
    @Published private(set) var disabledCount = 0
    @Published private(set) var ruleCount = 0
    @Published var isApplyingChange = false
    @Published var errorMessage: String?
    @Published var statusMessage = "Ready"

    /// Surfaces errors to the shell (for an alert) and notifies the module so the menu bar refreshes.
    var errorHandler: ((String) -> Void)?
    var snapshotDidChange: (() -> Void)?

    func load() {
        do {
            let snapshot = try HostsFileService.loadSnapshot()
            rules = snapshot.rules
            activeCount = snapshot.activeCount
            disabledCount = snapshot.disabledCount
            ruleCount = snapshot.rules.count
            statusMessage = "Loaded \(snapshot.rules.count) host rules."
            snapshotDidChange?()
        } catch {
            rules = []
            activeCount = 0
            disabledCount = 0
            ruleCount = 0
            handleError("Could not read /etc/hosts. \(error.localizedDescription)")
        }
    }

    @discardableResult
    func addRule(ipAddressesField: String, hostnamesField: String, comment: String, enabled: Bool = true) -> Bool {
        performChange(successMessage: "Host rule added.") {
            try HostsFileService.addRule(ipAddressesField: ipAddressesField, hostnamesField: hostnamesField, comment: comment, enabled: enabled)
        }
    }

    @discardableResult
    func removeRule(_ rule: HostRule) -> Bool {
        performChange(successMessage: "Host rule removed.") {
            try HostsFileService.removeRule(rule)
        }
    }

    @discardableResult
    func setRule(_ rule: HostRule, enabled: Bool) -> Bool {
        performChange(successMessage: enabled ? "Host rule enabled." : "Host rule disabled.") {
            try HostsFileService.setRule(rule, enabled: enabled)
        }
    }

    @discardableResult
    func updateRule(_ rule: HostRule, ipAddressesField: String, hostnamesField: String, comment: String, enabled: Bool) -> Bool {
        performChange(successMessage: "Host rule updated.") {
            try HostsFileService.updateRule(rule, ipAddressesField: ipAddressesField, hostnamesField: hostnamesField, comment: comment, enabled: enabled)
        }
    }

    private func performChange(successMessage: String, action: () throws -> Void) -> Bool {
        isApplyingChange = true
        defer { isApplyingChange = false }
        do {
            try action()
            load()
            statusMessage = successMessage
            return true
        } catch {
            handleError(error.localizedDescription)
            return false
        }
    }

    private func handleError(_ message: String) {
        errorMessage = message
        errorHandler?(message)
    }
}
