import Foundation

// A single non-empty, parseable line in /etc/hosts.
struct HostEntry: Identifiable, Hashable {
    let id: Int
    let originalLine: String
    let ipAddress: String
    let hostnames: [String]
    let comment: String
    let isEnabled: Bool

    var hostnamesJoined: String { hostnames.joined(separator: " ") }

    var displayTitle: String {
        let hostPart = hostnamesJoined.isEmpty ? "(no hostname)" : hostnamesJoined
        return "\(hostPart) -> \(ipAddress)"
    }
}

/// A logical rule: one or more entries that share the same hostnames + comment (e.g. an IPv4 and
/// IPv6 line for the same host).
struct HostRule: Identifiable, Hashable {
    let entries: [HostEntry]

    init(entries: [HostEntry]) {
        self.entries = entries.sorted { $0.id < $1.id }
    }

    var id: String { "\(entries.first?.id ?? -1)|\(groupingKey)" }
    var hostnames: [String] { entries.first?.hostnames ?? [] }
    var hostnamesJoined: String { hostnames.joined(separator: " ") }
    var comment: String { entries.first?.comment ?? "" }
    var ipAddresses: [String] { entries.map(\.ipAddress) }
    var ipAddressesJoined: String { ipAddresses.joined(separator: ", ") }

    var isEnabled: Bool { entries.allSatisfy(\.isEnabled) }
    var isPartiallyEnabled: Bool { !isEnabled && entries.contains(where: \.isEnabled) }
    var hasAnyEnabled: Bool { entries.contains(where: \.isEnabled) }

    var displayTitle: String {
        let hostPart = hostnamesJoined.isEmpty ? "(no hostname)" : hostnamesJoined
        return "\(hostPart) -> \(ipAddressesJoined)"
    }

    var accessibilityLabel: String { "\(stateLabel) rule \(displayTitle)" }

    var stateLabel: String {
        if isPartiallyEnabled { return "Partially enabled" }
        return isEnabled ? "Enabled" : "Disabled"
    }

    var groupingKey: String { Self.groupingKey(for: hostnames, comment: comment) }

    static func groupingKey(for hostnames: [String], comment: String) -> String {
        let normalizedHosts = hostnames.map { $0.lowercased() }.joined(separator: "\u{1F}")
        let normalizedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedHosts)#\(normalizedComment)"
    }
}

struct HostsSnapshot {
    let rawContents: String
    let rules: [HostRule]

    var activeCount: Int { rules.filter(\.hasAnyEnabled).count }
    var disabledCount: Int { rules.count - activeCount }
}

enum HostsError: LocalizedError {
    case missingHostnames
    case missingIPAddress
    case invalidIPAddress(String)
    case entryNotFound
    case scriptCreationFailed
    case adminCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingHostnames: return "Enter at least one hostname."
        case .missingIPAddress: return "Enter an IP address."
        case .invalidIPAddress(let value): return "`\(value)` is not a valid IPv4 or IPv6 address."
        case .entryNotFound: return "The selected host rule could not be found. Refresh and try again."
        case .scriptCreationFailed: return "The administrator prompt could not be prepared."
        case .adminCommandFailed(let details): return details
        }
    }
}
