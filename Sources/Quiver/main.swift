import AppKit

@main
struct QuiverMain {
    @MainActor
    static func main() {
        // Single-instance guard: if another Quiver is already running, surface it and exit.
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tirth.quiver"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [.activateAllWindows])
            return
        }

        let launchesInBackground = CommandLine.arguments.contains("--background")

        let app = NSApplication.shared
        let controller = AppController(launchesInBackground: launchesInBackground)
        app.delegate = controller
        // LSUIElement keeps us out of the Dock; the controller flips to .regular while a window is open.
        app.setActivationPolicy(launchesInBackground ? .accessory : .regular)
        app.run()
    }
}
