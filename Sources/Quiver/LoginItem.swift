import Foundation

/// Launch-at-login via a per-user LaunchAgent. Built on a proven mechanism:
/// it points the agent at the *installed* executable and can pass `--background` so Quiver
/// starts hidden in the menu bar at login.
enum LoginItem {
    static let label = "com.tirth.quiver.launcher"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func sync(enabled: Bool, launchHidden: Bool) throws {
        if enabled {
            try writePlist(launchHidden: launchHidden)
            try bootoutIfNeeded()
            try runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", plistURL.path])
        } else {
            try bootoutIfNeeded()
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func writePlist(launchHidden: Bool) throws {
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw QuiverError.message("Could not locate the installed app executable.")
        }

        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var arguments = [executablePath]
        if launchHidden { arguments.append("--background") }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive"
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    private static func bootoutIfNeeded() throws {
        try runLaunchctl(arguments: ["bootout", "gui/\(getuid())", plistURL.path], allowFailure: true)
    }

    private static func runLaunchctl(arguments: [String], allowFailure: Bool = false) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 || allowFailure { return }

        let output = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw QuiverError.message(output?.isEmpty == false
            ? output!
            : "launchctl failed with exit status \(process.terminationStatus).")
    }
}

/// Generic user-facing error used across the shell.
enum QuiverError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
