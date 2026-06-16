import Foundation

/// Streams bytes as they transfer and reports a rolling, instantaneous Mbps so the UI can tick live —
/// computed on the URLSession delegate queue and forwarded (throttled) to the main actor.
final class SpeedSampler: NSObject, URLSessionDataDelegate {
    /// (instantaneous Mbps, fraction complete 0…1) — invoked on the delegate queue, already throttled.
    var onSample: ((Double, Double) -> Void)?

    private var continuation: CheckedContinuation<(Int, Double), Error>?
    private var expected: Int64 = 0
    private var total: Int64 = 0
    private var startTime: CFAbsoluteTime = 0
    private var window: [(t: CFAbsoluteTime, bytes: Int64)] = []
    private var lastForward: CFAbsoluteTime = 0
    private let windowSeconds: CFAbsoluteTime = 1.0
    private let throttle: CFAbsoluteTime = 0.066   // ≤ ~15 Hz

    /// Arm the sampler for one transfer of `expected` bytes; resumes `continuation` when it completes.
    func begin(expected: Int64, _ continuation: CheckedContinuation<(Int, Double), Error>) {
        self.expected = expected
        total = 0
        startTime = 0
        window = []
        lastForward = 0
        self.continuation = continuation
    }

    private func record(newTotal: Int64) {
        let now = CFAbsoluteTimeGetCurrent()
        if startTime == 0 { startTime = now }
        total = newTotal
        window.append((now, total))
        while let first = window.first, now - first.t > windowSeconds { window.removeFirst() }

        if lastForward == 0 || now - lastForward >= throttle {
            lastForward = now
            let fraction = expected > 0 ? min(1, Double(total) / Double(expected)) : 0
            onSample?(instantMbps(now: now), fraction)
        }
    }

    private func instantMbps(now: CFAbsoluteTime) -> Double {
        guard let first = window.first, now - first.t > 0 else { return 0 }
        return Double(total - first.bytes) * 8 / (now - first.t) / 1_000_000
    }

    // Download: count each chunk (the bytes themselves are discarded — low memory).
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        record(newTotal: total + Int64(data.count))
    }

    // Upload: progress is reported as cumulative bytes sent.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if expected == 0 { expected = totalBytesExpectedToSend }
        record(newTotal: totalBytesSent)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let elapsed = startTime > 0 ? CFAbsoluteTimeGetCurrent() - startTime : 0
        let cont = continuation
        continuation = nil
        if let error { cont?.resume(throwing: error) } else { cont?.resume(returning: (Int(total), elapsed)) }
    }
}

/// Measures internet latency, download, and upload speed against Cloudflare's public, keyless speed
/// endpoints (the same ones behind speed.cloudflare.com), updating live as each transfer runs.
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

    // Live readings for the active phase.
    @Published private(set) var liveMbps: Double = 0
    @Published private(set) var progress: Double = 0
    @Published private(set) var samples: [Double] = []

    /// Routed to the module so failures reach the shell's alert.
    var onError: ((String) -> Void)?

    var isRunning: Bool { if case .running = state { return true }; return false }

    private var task: Task<Void, Never>?
    private var activeTask: URLSessionTask?
    private let downloadBytes = 50_000_000
    private let uploadBytes = 15_000_000

    private let sampler = SpeedSampler()
    private let latencySession: URLSession
    private let streamSession: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 30
        latencySession = URLSession(configuration: config)

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        streamSession = URLSession(configuration: config, delegate: sampler, delegateQueue: queue)

        sampler.onSample = { [weak self] mbps, fraction in
            DispatchQueue.main.async {
                guard let self else { return }
                self.liveMbps = mbps
                self.progress = fraction
                self.samples.append(mbps)
                if self.samples.count > 60 { self.samples.removeFirst(self.samples.count - 60) }
            }
        }
    }

    deinit { streamSession.invalidateAndCancel() }

    func run() {
        guard !isRunning else { return }
        task = Task { await perform() }
    }

    func cancel() {
        activeTask?.cancel()
        task?.cancel()
        task = nil
        activeTask = nil
        if isRunning { state = lastResult.map(State.finished) ?? .idle }
    }

    private func resetLive() {
        liveMbps = 0
        progress = 0
        samples = []
    }

    private func perform() async {
        do {
            resetLive()
            state = .running(.latency)
            let latency = try await measureLatency()
            try Task.checkCancellation()

            resetLive()
            state = .running(.download)
            let download = try await measure(expected: Int64(downloadBytes)) {
                self.streamSession.dataTask(with: URLRequest(
                    url: URL(string: "https://speed.cloudflare.com/__down?bytes=\(self.downloadBytes)")!))
            }
            try Task.checkCancellation()

            resetLive()
            state = .running(.upload)
            let upload = try await measure(expected: Int64(uploadBytes)) {
                var request = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!)
                request.httpMethod = "POST"
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                return self.streamSession.uploadTask(with: request, from: Data(count: self.uploadBytes))
            }

            let result = Result(latencyMs: latency, downloadMbps: download, uploadMbps: upload)
            lastResult = result
            state = .finished(result)
        } catch {
            if Self.isCancellation(error) {
                state = lastResult.map(State.finished) ?? .idle
            } else {
                let message = Self.friendlyError(error)
                state = .failed(message)
                onError?(message)
            }
        }
        activeTask = nil
    }

    /// Run a streaming `dataTask`/`uploadTask`, returning its average Mbps once it completes.
    private func measure(expected: Int64, makeTask: @escaping () -> URLSessionTask) async throws -> Double {
        let (bytes, seconds) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Int, Double), Error>) in
            sampler.begin(expected: expected, continuation)
            let task = makeTask()
            activeTask = task
            task.resume()
        }
        return Self.mbps(bytes: bytes, seconds: seconds)
    }

    private func measureLatency() async throws -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0")!
        var samples: [Double] = []
        for _ in 0..<5 {
            try Task.checkCancellation()
            let start = Date()
            _ = try await latencySession.data(from: url)
            samples.append(Date().timeIntervalSince(start) * 1000)
        }
        samples.sort()
        return samples[samples.count / 2]   // median (warms/reuses the connection)
    }

    private static func mbps(bytes: Int, seconds: Double) -> Double {
        seconds > 0 ? Double(bytes) * 8 / seconds / 1_000_000 : 0
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
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
