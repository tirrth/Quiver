import Combine
import SwiftUI

/// A quick internet speed check (download, upload, latency) from the menu bar, powered by Cloudflare's
/// public speed endpoints.
@MainActor
final class SpeedTestModule: UtilityModule {
    let service = SpeedTestService()
    private var cancellable: AnyCancellable?

    init() {
        super.init(
            id: "speedtest",
            title: "Speed Test",
            subtitle: "Check your internet download, upload, and latency without leaving the menu bar.",
            symbolName: "gauge.with.dots.needle.50percent",
            isToggleable: false
        )
        service.onError = { [weak self] message in self?.reportError(message) }
        cancellable = service.$state
            .sink { [weak self] _ in DispatchQueue.main.async { self?.notifyChange() } }
    }

    override var statusSummary: String {
        if case .running(let phase) = service.state { return "Testing \(phase.rawValue.lowercased())…" }
        if let result = service.lastResult {
            return "↓ \(SpeedTestService.mbpsString(result.downloadMbps)) · ↑ \(SpeedTestService.mbpsString(result.uploadMbps)) Mbps"
        }
        return "Run a test"
    }

    override func makeQuickControls() -> AnyView? {
        AnyView(SpeedTestQuickControls(module: self))
    }

    override func makeSettingsView() -> AnyView {
        AnyView(SpeedTestSettingsView(module: self))
    }
}
