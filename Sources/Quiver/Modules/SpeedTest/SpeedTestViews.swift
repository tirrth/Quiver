import SwiftUI

/// A tiny live line graph of recent samples.
private struct Sparkline: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(samples.max() ?? 1, 1)
            let w = geo.size.width, h = geo.size.height
            ZStack {
                if samples.count > 1 {
                    let points = samples.enumerated().map { index, value in
                        CGPoint(x: w * CGFloat(index) / CGFloat(samples.count - 1),
                                y: h - CGFloat(value / maxValue) * h)
                    }
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        points.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: w, y: h))
                        p.closeSubpath()
                    }
                    .fill(Color.accentColor.opacity(0.15))
                    Path { p in
                        p.move(to: points[0])
                        points.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

// MARK: - Live monitor

/// The always-on live readout: current download/upload throughput + a moving sparkline.
private struct LiveMonitor: View {
    @ObservedObject var monitor: NetworkMonitor
    let enabled: Bool

    var body: some View {
        if enabled {
            VStack(spacing: 7) {
                HStack(spacing: 14) {
                    rate("arrow.down", monitor.downloadMbps)
                    Divider().frame(height: 22)
                    rate("arrow.up", monitor.uploadMbps)
                }
                Sparkline(samples: monitor.downloadSamples).frame(height: 30)
            }
        } else {
            Text("Turn on Net Speed to watch your live download and upload speed.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rate(_ symbol: String, _ mbps: Double) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.accentColor)
            Text(NetworkMonitor.rateString(mbps)).font(.system(size: 16, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - On-demand full speed test (Cloudflare saturation test)

private struct SpeedMetrics: View {
    let result: SpeedTestService.Result?

    var body: some View {
        HStack(spacing: 0) {
            metric("arrow.down", result.map { SpeedTestService.mbpsString($0.downloadMbps) }, "Mbps")
            Divider().frame(height: 26)
            metric("arrow.up", result.map { SpeedTestService.mbpsString($0.uploadMbps) }, "Mbps")
            Divider().frame(height: 26)
            metric("timer", result.map { SpeedTestService.latencyString($0.latencyMs) }, "ms")
        }
    }

    private func metric(_ symbol: String, _ value: String?, _ unit: String) -> some View {
        VStack(spacing: 1) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(value ?? "—").font(.system(size: 15, weight: .semibold)).monospacedDigit()
            Text(unit).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LiveTestReadout: View {
    let phase: SpeedTestService.Phase
    let mbps: Double
    let progress: Double
    let samples: [Double]

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: phase == .download ? "arrow.down" : "arrow.up")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.accentColor)
                Text(SpeedTestService.mbpsString(mbps)).font(.system(size: 26, weight: .bold)).monospacedDigit()
                Text("Mbps").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text("\(phase.rawValue)…").font(.caption).foregroundStyle(.secondary)
            }
            Sparkline(samples: samples).frame(height: 32)
            ProgressView(value: min(max(progress, 0), 1))
        }
    }
}

/// The Run-Test body: live readout while testing, latency spinner, else final metrics.
private struct TestBody: View {
    @ObservedObject var service: SpeedTestService

    var body: some View {
        switch service.state {
        case .running(.latency):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Measuring latency…").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(height: 64)
        case .running(let phase):
            LiveTestReadout(phase: phase, mbps: service.liveMbps, progress: service.progress, samples: service.samples)
        default:
            SpeedMetrics(result: service.lastResult)
        }
    }
}

private struct RunButton: View {
    @ObservedObject var service: SpeedTestService

    var body: some View {
        if service.isRunning {
            Button { service.cancel() } label: { Label("Cancel", systemImage: "stop.fill") }
        } else {
            Button { service.run() } label: { Label("Run Test", systemImage: "play.fill") }
        }
    }
}

// MARK: - Module views

/// Inline controls shown in the menu-bar popover.
struct SpeedTestQuickControls: View {
    @ObservedObject var module: SpeedTestModule
    @ObservedObject private var monitor: NetworkMonitor
    @ObservedObject private var tester: SpeedTestService

    init(module: SpeedTestModule) {
        self.module = module
        self.monitor = module.monitor
        self.tester = module.tester
    }

    var body: some View {
        VStack(spacing: 10) {
            LiveMonitor(monitor: monitor, enabled: module.isEnabled)
            Divider()
            HStack {
                Text("Full speed test").font(.caption).foregroundStyle(.secondary)
                Spacer()
                RunButton(service: tester).controlSize(.small)
            }
            if tester.isRunning || tester.lastResult != nil {
                TestBody(service: tester)
            }
        }
    }
}

/// Full settings pane.
struct SpeedTestSettingsView: View {
    @ObservedObject var module: SpeedTestModule
    @ObservedObject private var monitor: NetworkMonitor
    @ObservedObject private var tester: SpeedTestService

    init(module: SpeedTestModule) {
        self.module = module
        self.monitor = module.monitor
        self.tester = module.tester
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Live Speed") {
                LiveMonitor(monitor: monitor, enabled: module.isEnabled).padding(.vertical, 2)
                if module.isEnabled {
                    Text("Pin Net Speed (Show in menu bar) to keep this readout in the menu bar.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Card(title: "Speed Test") {
                TestBody(service: tester).padding(.vertical, 2)
                Divider()
                HStack {
                    if case .failed(let message) = tester.state {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    RunButton(service: tester).buttonStyle(.borderedProminent)
                }
                Text("Measures max capacity against Cloudflare’s servers — transfers about 65 MB of data.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
