import Darwin
import Foundation

// Parses, rewrites, and privileged-writes /etc/hosts.
enum HostsFileService {
    static let hostsURL = URL(fileURLWithPath: "/etc/hosts")

    static func loadSnapshot() throws -> HostsSnapshot {
        let contents = try String(contentsOf: hostsURL, encoding: .utf8)
        let entries = parseEntries(from: contents)
        return HostsSnapshot(rawContents: contents, rules: groupRules(from: entries))
    }

    static func addRule(ipAddressesField: String, hostnamesField: String, comment: String, enabled: Bool = true) throws {
        let newLines = try makeRuleLines(ipAddressesField: ipAddressesField, hostnamesField: hostnamesField, comment: comment, enabled: enabled)
        let current = try String(contentsOf: hostsURL, encoding: .utf8)
        let appendedLines = newLines.joined(separator: "\n")
        let updated: String
        if current.isEmpty {
            updated = appendedLines + "\n"
        } else if current.hasSuffix("\n") {
            updated = current + appendedLines + "\n"
        } else {
            updated = current + "\n" + appendedLines + "\n"
        }
        try writePrivileged(contents: updated)
    }

    static func removeRule(_ rule: HostRule) throws {
        let current = try String(contentsOf: hostsURL, encoding: .utf8)
        var lines = current.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let indices = try lineIndices(for: rule, in: lines)
        for index in indices.sorted(by: >) { lines.remove(at: index) }
        try writePrivileged(contents: updatedContents(from: lines, preservingTrailingNewlineOf: current))
    }

    static func setRule(_ rule: HostRule, enabled: Bool) throws {
        let current = try String(contentsOf: hostsURL, encoding: .utf8)
        var lines = current.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let indices = try lineIndices(for: rule, in: lines)
        for index in indices { lines[index] = rewriteLine(lines[index], enabled: enabled) }
        try writePrivileged(contents: updatedContents(from: lines, preservingTrailingNewlineOf: current))
    }

    static func updateRule(_ rule: HostRule, ipAddressesField: String, hostnamesField: String, comment: String, enabled: Bool) throws {
        let replacementLines = try makeRuleLines(ipAddressesField: ipAddressesField, hostnamesField: hostnamesField, comment: comment, enabled: enabled)
        let current = try String(contentsOf: hostsURL, encoding: .utf8)
        var lines = current.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let indices = try lineIndices(for: rule, in: lines)
        guard let insertionIndex = indices.min() else { throw HostsError.entryNotFound }
        for index in indices.sorted(by: >) { lines.remove(at: index) }
        lines.insert(contentsOf: replacementLines, at: insertionIndex)
        try writePrivileged(contents: updatedContents(from: lines, preservingTrailingNewlineOf: current))
    }

    static func moveRule(_ rule: HostRule, to destinationIndex: Int) throws {
        let current = try String(contentsOf: hostsURL, encoding: .utf8)
        var lines = current.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let entries = parseEntries(from: current)
        var rules = groupRules(from: entries)

        guard let sourceIndex = indexOfRule(rule, in: rules) else { throw HostsError.entryNotFound }

        let movedRule = rules.remove(at: sourceIndex)
        let clampedDestination = max(0, min(destinationIndex, rules.count))
        let adjustedDestination = sourceIndex < clampedDestination ? clampedDestination - 1 : clampedDestination
        if adjustedDestination == sourceIndex { return }
        rules.insert(movedRule, at: adjustedDestination)

        let ruleLineIndices = lines.enumerated().compactMap { index, line in
            parseEntry(from: line, lineNumber: index) == nil ? nil : index
        }
        let reorderedEntries = rules.flatMap(\.entries)
        guard ruleLineIndices.count == reorderedEntries.count else {
            throw HostsError.adminCommandFailed("Quiver could not safely reorder the rules. Refresh and try again.")
        }
        for (entry, lineIndex) in zip(reorderedEntries, ruleLineIndices) { lines[lineIndex] = entry.originalLine }
        try writePrivileged(contents: updatedContents(from: lines, preservingTrailingNewlineOf: current))
    }

    private static func groupRules(from entries: [HostEntry]) -> [HostRule] {
        var groupedEntries: [String: [HostEntry]] = [:]
        var orderedKeys: [String] = []
        for entry in entries {
            let key = HostRule.groupingKey(for: entry.hostnames, comment: entry.comment)
            if groupedEntries[key] == nil {
                groupedEntries[key] = []
                orderedKeys.append(key)
            }
            groupedEntries[key]?.append(entry)
        }
        return orderedKeys.compactMap { key in
            guard let grouped = groupedEntries[key], !grouped.isEmpty else { return nil }
            return HostRule(entries: grouped)
        }
    }

    private static func parseEntries(from contents: String) -> [HostEntry] {
        contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            parseEntry(from: String(line), lineNumber: index)
        }
    }

    private static func parseEntry(from line: String, lineNumber: Int) -> HostEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let isEnabled = !trimmed.hasPrefix("#")
        let candidateLine: String
        if isEnabled {
            candidateLine = trimmed
        } else {
            candidateLine = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard !candidateLine.isEmpty else { return nil }

        let pieces = candidateLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let mapping = pieces[0].trimmingCharacters(in: .whitespaces)
        let comment = pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespaces) : ""
        let tokens = mapping.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2, isSupportedAddress(tokens[0]) else { return nil }

        return HostEntry(
            id: lineNumber,
            originalLine: line,
            ipAddress: tokens[0],
            hostnames: Array(tokens.dropFirst()),
            comment: comment,
            isEnabled: isEnabled
        )
    }

    private static func lineIndices(for rule: HostRule, in lines: [String]) throws -> [Int] {
        var matchedIndices: [Int] = []
        var consumedIndices = Set<Int>()
        for entry in rule.entries.sorted(by: { $0.id < $1.id }) {
            if entry.id < lines.count, lines[entry.id] == entry.originalLine, !consumedIndices.contains(entry.id) {
                matchedIndices.append(entry.id)
                consumedIndices.insert(entry.id)
                continue
            }
            if let fallbackIndex = lines.indices.first(where: { !consumedIndices.contains($0) && lines[$0] == entry.originalLine }) {
                matchedIndices.append(fallbackIndex)
                consumedIndices.insert(fallbackIndex)
                continue
            }
            throw HostsError.entryNotFound
        }
        return matchedIndices.sorted()
    }

    private static func indexOfRule(_ rule: HostRule, in rules: [HostRule]) -> Int? {
        if let exactMatch = rules.firstIndex(where: { $0.entries == rule.entries }) { return exactMatch }
        return rules.firstIndex(where: {
            $0.groupingKey == rule.groupingKey && $0.hostnames == rule.hostnames &&
            $0.comment == rule.comment && $0.ipAddresses == rule.ipAddresses
        })
    }

    private static func makeRuleLines(ipAddressesField: String, hostnamesField: String, comment: String, enabled: Bool) throws -> [String] {
        let normalizedIPs = normalizeAddressField(ipAddressesField)
        let normalizedHosts = hostnamesField.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init).filter { !$0.isEmpty }
        guard !normalizedIPs.isEmpty else { throw HostsError.missingIPAddress }
        if let invalidIP = normalizedIPs.first(where: { !isSupportedAddress($0) }) { throw HostsError.invalidIPAddress(invalidIP) }
        guard !normalizedHosts.isEmpty else { throw HostsError.missingHostnames }
        let normalizedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedIPs.map { ipAddress in
            var line = ([ipAddress] + normalizedHosts).joined(separator: " ")
            if !normalizedComment.isEmpty { line += " # \(normalizedComment)" }
            if !enabled { line = "# " + line }
            return line
        }
    }

    private static func normalizeAddressField(_ field: String) -> [String] {
        field.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init).filter { !$0.isEmpty }
    }

    private static func updatedContents(from lines: [String], preservingTrailingNewlineOf original: String) -> String {
        var updated = lines.joined(separator: "\n")
        if original.hasSuffix("\n"), !updated.hasSuffix("\n") { updated += "\n" }
        return updated
    }

    private static func rewriteLine(_ line: String, enabled: Bool) -> String {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        var remainder = String(line.dropFirst(indentation.count))
        if enabled {
            if remainder.hasPrefix("#") {
                remainder.removeFirst()
                while remainder.first == " " || remainder.first == "\t" { remainder.removeFirst() }
            }
            return indentation + remainder
        }
        if remainder.hasPrefix("#") { return line }
        return indentation + "# " + remainder
    }

    private static func isSupportedAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return value.withCString { pointer in
            inet_pton(AF_INET, pointer, &ipv4) == 1 || inet_pton(AF_INET6, pointer, &ipv6) == 1
        }
    }

    private static func writePrivileged(contents: String) throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Quiver-\(UUID().uuidString).tmp")
        try contents.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        if PasswordlessHostsWriter.isInstalled {
            try PasswordlessHostsWriter.apply(sourceFileURL: tempURL)
            return
        }

        let command = [
            "/usr/bin/install -m 644 -o root -g wheel \(PrivilegedCommandRunner.shellQuoted(tempURL.path)) /etc/hosts",
            "/usr/bin/dscacheutil -flushcache",
            "(/usr/bin/killall -HUP mDNSResponder >/dev/null 2>&1 || true)"
        ].joined(separator: " && ")
        try PrivilegedCommandRunner.runWithAdministratorPrivileges(command)
    }
}
