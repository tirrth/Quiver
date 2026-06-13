import Foundation
import OSLog

/// Lightweight logging facade. Verbose console mirroring can be toggled from Settings.
enum Log {
    static let subsystem = "com.tirth.quiver"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let module = Logger(subsystem: subsystem, category: "module")

    /// When true, important events are also printed to stdout (useful when launched from a terminal).
    static var verbose = UserDefaults.standard.bool(forKey: "app.verboseLogging")

    static func info(_ message: String) {
        app.info("\(message, privacy: .public)")
        if verbose { print("[Quiver] \(message)") }
    }

    static func error(_ message: String) {
        app.error("\(message, privacy: .public)")
        if verbose { FileHandle.standardError.write(Data("[Quiver][error] \(message)\n".utf8)) }
    }
}
