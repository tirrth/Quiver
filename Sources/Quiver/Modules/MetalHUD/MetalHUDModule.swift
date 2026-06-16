import SwiftUI

/// Toggles Apple's Metal Performance HUD (FPS / GPU / memory overlay) for the GUI login session via
/// `launchctl setenv MTL_HUD_ENABLED`. Apps pick it up when launched, so toggling affects apps started
/// afterwards — already-running apps keep their current state.
@MainActor
final class MetalHUDModule: UtilityModule {
    init() {
        super.init(
            id: "metalhud",
            title: "Metal HUD",
            subtitle: "Show Apple's Metal performance overlay (FPS, GPU, and memory) on apps and games you launch.",
            symbolName: "waveform"
        )
    }

    override func start() { applyHUD(true) }
    override func stop() { applyHUD(false) }

    override var statusSummary: String { isEnabled ? "On · new apps show the HUD" : "Off" }

    override func makeSettingsView() -> AnyView { AnyView(MetalHUDSettingsView(module: self)) }

    private func applyHUD(_ on: Bool) {
        let value = on ? "1" : "0"
        Task.detached(priority: .userInitiated) {
            if let error = Self.runLaunchctl(value: value) {
                await MainActor.run { self.reportError(error) }
            }
        }
    }

    /// Sets the env var for the user's launchd (GUI) session. Runs off the main thread.
    nonisolated private static func runLaunchctl(value: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["setenv", "MTL_HUD_ENABLED", value]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                return "Couldn’t change the Metal HUD setting (launchctl exited \(process.terminationStatus))."
            }
            return nil
        } catch {
            return "Couldn’t change the Metal HUD setting: \(error.localizedDescription)"
        }
    }
}
