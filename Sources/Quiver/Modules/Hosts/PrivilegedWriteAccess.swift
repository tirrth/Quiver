import AppKit
import Foundation

// Ported from HostsMachine, rebranded to Quiver.
enum PrivilegedCommandRunner {
    static func runWithAdministratorPrivileges(_ command: String) throws {
        let scriptSource = "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
        guard let script = NSAppleScript(source: scriptSource) else {
            throw HostsError.scriptCreationFailed
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "macOS rejected the privileged command."
            throw HostsError.adminCommandFailed(message)
        }
    }

    static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// Installs (once, with an admin prompt) a small root-owned helper so later /etc/hosts edits don't
/// prompt for a password. The helper only ever replaces /etc/hosts from a Quiver temp file.
enum PasswordlessHostsWriter {
    static let helperInstallURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.tirth.quiver.hostshelper")
    private static let helperResourceName = "QuiverHelper"

    static var isInstalled: Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: helperInstallURL.path) else {
            return false
        }
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.intValue ?? -1
        let group = (attributes[.groupOwnerAccountID] as? NSNumber)?.intValue ?? -1
        return permissions == 0o4755 && owner == 0 && group == 0
    }

    static func installFromBundle() throws {
        guard let bundledHelperURL = Bundle.main.url(forResource: helperResourceName, withExtension: nil) else {
            throw HostsError.adminCommandFailed("The bundled privileged helper is missing from the app.")
        }
        let command = [
            "/usr/bin/install -d -m 755 -o root -g wheel /Library/PrivilegedHelperTools",
            "/usr/bin/install -m 4755 -o root -g wheel \(PrivilegedCommandRunner.shellQuoted(bundledHelperURL.path)) \(PrivilegedCommandRunner.shellQuoted(helperInstallURL.path))"
        ].joined(separator: " && ")
        try PrivilegedCommandRunner.runWithAdministratorPrivileges(command)
    }

    static func uninstall() throws {
        let command = "/bin/rm -f \(PrivilegedCommandRunner.shellQuoted(helperInstallURL.path))"
        try PrivilegedCommandRunner.runWithAdministratorPrivileges(command)
    }

    static func apply(sourceFileURL: URL) throws {
        let process = Process()
        process.executableURL = helperInstallURL
        process.arguments = ["apply", sourceFileURL.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let details = [stderr, stdout].compactMap { $0 }.first { !$0.isEmpty }
            if let details, details.localizedCaseInsensitiveContains("root") {
                throw HostsError.adminCommandFailed("Passwordless mode is not fully active. Open the Hosts utility and re-enable passwordless writes once.")
            }
            throw HostsError.adminCommandFailed(details ?? "The privileged helper failed to update /etc/hosts.")
        }
    }
}
