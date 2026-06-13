import Foundation

// Root-owned helper installed by Quiver's Hosts utility. It only ever replaces /etc/hosts from a
// Quiver-owned temp file, then flushes DNS caches. Ported from HostsMachineHelper.
private enum HelperError: LocalizedError {
    case notRoot
    case invalidArguments
    case invalidSourceFile
    case invalidContents
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRoot: return "Quiver helper must run as root."
        case .invalidArguments: return "Usage: com.tirth.quiver.hostshelper apply /path/to/Quiver-*.tmp"
        case .invalidSourceFile: return "The source file is not a valid Quiver temporary file."
        case .invalidContents: return "The source file does not contain valid UTF-8 hosts contents."
        case .commandFailed(let message): return message
        }
    }
}

@main
struct QuiverHelperMain {
    static func main() {
        do {
            try run()
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        guard geteuid() == 0 else { throw HelperError.notRoot }

        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2, arguments[0] == "apply" else { throw HelperError.invalidArguments }

        let sourceURL = URL(fileURLWithPath: arguments[1])
        try validateSource(sourceURL)

        let data = try Data(contentsOf: sourceURL)
        guard String(data: data, encoding: .utf8) != nil else { throw HelperError.invalidContents }

        let hostsURL = URL(fileURLWithPath: "/etc/hosts")
        try data.write(to: hostsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: hostsURL.path)
        try runProcess("/usr/sbin/chown", ["root:wheel", hostsURL.path])
        try runProcess("/usr/bin/dscacheutil", ["-flushcache"])
        try runProcess("/usr/bin/killall", ["-HUP", "mDNSResponder"], allowFailure: true)
    }

    private static func validateSource(_ sourceURL: URL) throws {
        let fileName = sourceURL.lastPathComponent
        guard fileName.hasPrefix("Quiver-"), fileName.hasSuffix(".tmp") else {
            throw HelperError.invalidSourceFile
        }
        var fileStat = stat()
        guard lstat(sourceURL.path, &fileStat) == 0 else { throw HelperError.invalidSourceFile }
        guard (fileStat.st_mode & S_IFMT) == S_IFREG else { throw HelperError.invalidSourceFile }
        guard fileStat.st_uid == getuid() else { throw HelperError.invalidSourceFile }
        if fileStat.st_size > 1_000_000 { throw HelperError.invalidSourceFile }
    }

    private static func runProcess(_ launchPath: String, _ arguments: [String], allowFailure: Bool = false) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 || allowFailure { return }
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw HelperError.commandFailed(stderr?.isEmpty == false ? stderr! : "\(launchPath) failed with exit status \(process.terminationStatus).")
    }
}
