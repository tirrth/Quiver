import Foundation

/// Live network throughput monitor. On recent Apple-Silicon macOS the `getifaddrs`/`if_data` interface
/// byte counters are unreliable (received bytes read 0), so this drives Apple's `nettop` tool — the same
/// per-process flow stats Activity Monitor uses — in cumulative mode and computes per-second deltas per
/// process itself (nettop's own `-d` delta mode proved unreliable). Passive, zero data cost; Mbps.
final class NetworkMonitor: ObservableObject {
    @Published private(set) var downloadMbps: Double = 0
    @Published private(set) var uploadMbps: Double = 0
    @Published private(set) var downloadSamples: [Double] = []
    @Published private(set) var uploadSamples: [Double] = []

    private var process: Process?
    private var pipe: Pipe?

    // Parser state (only touched on the main queue). We diff each process's cumulative byte counts
    // between consecutive 1-second blocks, summing only positive per-process deltas — so a process
    // exiting can't dip the total and a newly-seen process can't spike it.
    private var lineBuffer = ""
    private var pending: [String: (inBytes: Double, outBytes: Double)] = [:]
    private var previous: [String: (inBytes: Double, outBytes: Double)] = [:]
    private var hasBaseline = false

    var isRunning: Bool { process != nil }

    func start() {
        guard process == nil else { return }
        resetParser()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -P per-process, -s 1 every second, -L 0 stream forever, -x raw, -J pick columns (cumulative).
        process.arguments = ["-P", "-s", "1", "-L", "0", "-x", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.ingest(text) }
        }

        do {
            try process.run()
        } catch {
            return   // nettop missing/failed — monitor just stays at 0
        }
        self.pipe = pipe
        self.process = process
    }

    func stop() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        pipe = nil
        downloadMbps = 0
        uploadMbps = 0
        downloadSamples = []
        uploadSamples = []
        resetParser()
    }

    deinit { process?.terminate() }

    private func resetParser() {
        lineBuffer = ""
        pending = [:]
        previous = [:]
        hasBaseline = false
    }

    private func ingest(_ text: String) {
        lineBuffer += text
        while let newline = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<newline])
            lineBuffer.removeSubrange(...newline)
            handle(line: line)
        }
    }

    private func handle(line: String) {
        if line.contains("bytes_in") {   // header line: the block just accumulated in `pending` is complete
            if hasBaseline {
                var deltaIn = 0.0
                var deltaOut = 0.0
                for (label, current) in pending {
                    guard let prior = previous[label] else { continue }   // new process this tick → skip
                    let di = current.inBytes - prior.inBytes;   if di > 0 { deltaIn += di }
                    let dout = current.outBytes - prior.outBytes; if dout > 0 { deltaOut += dout }
                }
                downloadMbps = deltaIn * 8 / 1_000_000
                uploadMbps = deltaOut * 8 / 1_000_000
                Self.appendCapped(&downloadSamples, downloadMbps)
                Self.appendCapped(&uploadSamples, uploadMbps)
            }
            previous = pending
            pending = [:]
            hasBaseline = true
            return
        }
        // Data row: "name.pid,bytes_in,bytes_out,"
        let columns = line.split(separator: ",", omittingEmptySubsequences: false)
        guard columns.count >= 3, let inBytes = Double(columns[1]), let outBytes = Double(columns[2]) else { return }
        pending[String(columns[0])] = (inBytes, outBytes)
    }

    private static func appendCapped(_ array: inout [Double], _ value: Double) {
        array.append(value)
        if array.count > 60 { array.removeFirst(array.count - 60) }
    }

    /// Full rate label for the popover, e.g. "2.4 Mbps" / "340 Kbps".
    static func rateString(_ mbps: Double) -> String {
        if mbps >= 1000 { return String(format: "%.1f Gbps", mbps / 1000) }
        if mbps >= 100 { return String(format: "%.0f Mbps", mbps) }
        if mbps >= 1 { return String(format: "%.1f Mbps", mbps) }
        return String(format: "%.0f Kbps", mbps * 1000)
    }

    /// Compact number for the menu-bar readout, e.g. "2.4" / "340K" / "1.2G".
    static func menuBarNumber(_ mbps: Double) -> String {
        if mbps >= 1000 { return String(format: "%.1fG", mbps / 1000) }
        if mbps >= 100 { return String(format: "%.0f", mbps) }
        if mbps >= 1 { return String(format: "%.1f", mbps) }
        if mbps >= 0.05 { return String(format: "%.0fK", mbps * 1000) }
        return "0"
    }
}
