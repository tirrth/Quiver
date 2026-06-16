import Foundation

/// Measures internet latency, download, and upload speed against Cloudflare's public, keyless speed
/// endpoints (the same ones behind speed.cloudflare.com). Cancelable; results published for the UI.
@MainActor
final class SpeedTestService: ObservableObject {
    struct Result: Equatable {
        var latencyMs: Double
        var downloadMbps: Double
        var uploadMbps: Double
    }

    enum Phase: String, Equatable { case latency = "Latency", download = "Download", upload = "Upload" }

    enum State: Equatable {
        case idle
        case running(Phase)
        case finished(Result)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastResult: Result?

    /// Routed to the module so failures reach the shell's alert.
    var onError: ((String) -> Void)?

    var isRunning: Bool { if case .running = state { return true }; return false }

    private var task: Task<Void, Never>?
    private let downloadBytes = 25_000_000
    private let uploadBytes = 10_000_000

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    func run() {
        guard !isRunning else { return }
        task = Task { await perform() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isRunning { state = lastResult.map(State.finished) ?? .idle }
    }

    private func perform() async {
        do {
            state = .running(.latency)
            let latency = try await measureLatency()
            try Task.checkCancellation()

            state = .running(.download)
            let download = try await measureDownload()
            try Task.checkCancellation()

            state = .running(.upload)
            let upload = try await measureUpload()

            let result = Result(latencyMs: latency, downloadMbps: download, uploadMbps: upload)
            lastResult = result
            state = .finished(result)
        } catch is CancellationError {
            state = lastResult.map(State.finished) ?? .idle
        } catch {
            let message = Self.friendlyError(error)
            state = .failed(message)
            onError?(message)
        }
    }

    private func measureLatency() async throws -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
        var samples: [Double] = []
        for _ in 0..<5 {
            try Task.checkCancellation()
            let start = Date()
            _ = try await session.data(from: url)
            samples.append(Date().timeIntervalSince(start) * 1000)
        }
        samples.sort()
        return samples[samples.count / 2]   // median (warms/reuses the connection)
    }

    private func measureDownload() async throws -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(downloadBytes)")!
        let start = Date()
        let (data, _) = try await session.data(from: url)
        return Self.mbps(bytes: data.count, seconds: Date().timeIntervalSince(start))
    }

    private func measureUpload() async throws -> Double {
        var request = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let payload = Data(count: uploadBytes)
        let start = Date()
        _ = try await session.upload(for: request, from: payload)
        return Self.mbps(bytes: uploadBytes, seconds: Date().timeIntervalSince(start))
    }

    private static func mbps(bytes: Int, seconds: Double) -> Double {
        seconds > 0 ? Double(bytes) * 8 / seconds / 1_000_000 : 0
    }

    private static func friendlyError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return "No internet connection."
            case NSURLErrorTimedOut:
                return "The speed test timed out."
            default: break
            }
        }
        return "Speed test failed: \(error.localizedDescription)"
    }

    static func mbpsString(_ value: Double) -> String { String(format: "%.0f", value) }
    static func latencyString(_ ms: Double) -> String { String(format: "%.0f", ms) }
}
