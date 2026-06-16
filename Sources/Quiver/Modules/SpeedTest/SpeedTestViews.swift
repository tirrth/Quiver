import SwiftUI

/// Shared result row: three metrics (download / upload / latency).
private struct SpeedMetrics: View {
    let result: SpeedTestService.Result?
    let runningPhase: SpeedTestService.Phase?

    var body: some View {
        HStack(spacing: 0) {
            metric("arrow.down", value: result.map { SpeedTestService.mbpsString($0.downloadMbps) },
                   unit: "Mbps", active: runningPhase == .download)
            Divider().frame(height: 26)
            metric("arrow.up", value: result.map { SpeedTestService.mbpsString($0.uploadMbps) },
                   unit: "Mbps", active: runningPhase == .upload)
            Divider().frame(height: 26)
            metric("timer", value: result.map { SpeedTestService.latencyString($0.latencyMs) },
                   unit: "ms", active: runningPhase == .latency)
        }
    }

    private func metric(_ symbol: String, value: String?, unit: String, active: Bool) -> some View {
        VStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? Color.accentColor : .secondary)
            Text(value ?? "—").font(.system(size: 15, weight: .semibold)).monospacedDigit()
            Text(unit).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

/// Inline controls shown in the menu-bar popover.
struct SpeedTestQuickControls: View {
    @ObservedObject var module: SpeedTestModule
    @ObservedObject private var service: SpeedTestService

    init(module: SpeedTestModule) {
        self.module = module
        self.service = module.service
    }

    private var runningPhase: SpeedTestService.Phase? {
        if case .running(let phase) = service.state { return phase }
        return nil
    }

    var body: some View {
        VStack(spacing: 8) {
            SpeedMetrics(result: service.lastResult, runningPhase: runningPhase)
            HStack {
                if case .running(let phase) = service.state {
                    ProgressView().controlSize(.small)
                    Text("Measuring \(phase.rawValue.lowercased())…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                RunButton(service: service).controlSize(.small)
            }
        }
    }
}

/// Full settings pane.
struct SpeedTestSettingsView: View {
    @ObservedObject var module: SpeedTestModule
    @ObservedObject private var service: SpeedTestService

    init(module: SpeedTestModule) {
        self.module = module
        self.service = module.service
    }

    private var runningPhase: SpeedTestService.Phase? {
        if case .running(let phase) = service.state { return phase }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Internet Speed") {
                SpeedMetrics(result: service.lastResult, runningPhase: runningPhase)
                    .padding(.vertical, 4)

                Divider()

                HStack {
                    if case .running(let phase) = service.state {
                        ProgressView().controlSize(.small)
                        Text("Measuring \(phase.rawValue.lowercased())…").font(.callout).foregroundStyle(.secondary)
                    } else if case .failed(let message) = service.state {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    RunButton(service: service).buttonStyle(.borderedProminent)
                }
            }

            Text("Measured against Cloudflare’s speed servers. A full test transfers about 35 MB of data.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
