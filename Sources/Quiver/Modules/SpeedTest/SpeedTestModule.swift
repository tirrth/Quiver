import Combine
import SwiftUI

/// Live network-speed monitor: while enabled, shows current download/upload throughput in real time
/// (menu bar + popover). Also offers an on-demand full speed test (max capacity via Cloudflare).
@MainActor
final class SpeedTestModule: UtilityModule {
    let monitor = NetworkMonitor()
    let tester = SpeedTestService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(
            id: "speedtest",
            title: "Net Speed",
            subtitle: "Watch your live download and upload speed in the menu bar, and run a full speed test on demand.",
            symbolName: "gauge.with.dots.needle.50percent",
            isToggleable: true
        )
        tester.onError = { [weak self] message in self?.reportError(message) }
        // Live monitor ticks → refresh the menu-bar readout + hub row each second.
        monitor.$downloadMbps
            .sink { [weak self] _ in DispatchQueue.main.async { self?.notifyChange() } }
            .store(in: &cancellables)
        tester.$state
            .sink { [weak self] _ in DispatchQueue.main.async { self?.notifyChange() } }
            .store(in: &cancellables)
    }

    override func start() { monitor.start() }
    override func stop() { monitor.stop() }

    override var statusSummary: String {
        guard isEnabled else { return "Off" }
        return "↓ \(NetworkMonitor.rateString(monitor.downloadMbps)) · ↑ \(NetworkMonitor.rateString(monitor.uploadMbps))"
    }

    /// Compact live readout shown in the menu bar when enabled (and pinned).
    override var menuBarTitle: String? {
        guard isEnabled else { return nil }
        return "↓\(NetworkMonitor.menuBarNumber(monitor.downloadMbps)) ↑\(NetworkMonitor.menuBarNumber(monitor.uploadMbps))"
    }

    override func makeQuickControls() -> AnyView? {
        AnyView(SpeedTestQuickControls(module: self))
    }

    override func makeSettingsView() -> AnyView {
        AnyView(SpeedTestSettingsView(module: self))
    }
}
