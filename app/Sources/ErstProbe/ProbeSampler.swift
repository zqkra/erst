import ErstKit
import Foundation

/// One reading taken while the recorder runs.
struct ProbeSample: Sendable {
    let uptimeSeconds: Double
    let cpuSeconds: Double
    let residentBytes: UInt64
    let framesSeen: Int
    let framesKept: Int
}

/// The change between two adjacent readings.
struct ProbeSamplePair: Sendable {
    /// Process uptime when the earlier reading was taken, where this sample starts.
    let startUptimeSeconds: Double
    let elapsedSeconds: Double
    let cpuPercent: Double
    let framesSeenDelta: Int
    let framesKeptDelta: Int
    let residentBytes: UInt64
}

/// CPU spent while capture delivered a frame and the keep policy rejected every one.
struct ProbeStaticCPU: Sendable {
    let pairs: [ProbeSamplePair]

    var seconds: Double {
        pairs.reduce(0) { $0 + $1.elapsedSeconds }
    }

    /// Weighted by each sample's elapsed time, so an uneven tick does not skew the mean.
    var percent: Double? {
        let seconds = self.seconds
        guard seconds > 0 else { return nil }
        return pairs.reduce(0) { $0 + $1.cpuPercent * $1.elapsedSeconds } / seconds
    }
}

/// Everything the summary needs from the one-second samples.
struct ProbeSampleHistory: Sendable {
    let samples: [ProbeSample]

    var pairs: [ProbeSamplePair] {
        guard samples.count > 1 else { return [] }
        return zip(samples, samples.dropFirst()).compactMap { previous, current in
            let elapsed = current.uptimeSeconds - previous.uptimeSeconds
            guard elapsed > 0 else { return nil }
            let cpu = (current.cpuSeconds - previous.cpuSeconds) / elapsed * 100
            return ProbeSamplePair(
                startUptimeSeconds: previous.uptimeSeconds,
                elapsedSeconds: elapsed,
                cpuPercent: max(0, cpu),
                framesSeenDelta: current.framesSeen - previous.framesSeen,
                framesKeptDelta: current.framesKept - previous.framesKept,
                residentBytes: current.residentBytes
            )
        }
    }

    /// Seconds in which capture delivered a frame and the keep policy rejected every one.
    ///
    /// The sample after a kept frame can still contain that frame's OCR work, so this is an
    /// upper bound on static-screen CPU, not a lower bound.
    var staticPairs: [ProbeSamplePair] {
        pairs.filter { $0.framesSeenDelta > 0 && $0.framesKeptDelta == 0 }
    }

    /// The static-screen samples that start at or after the given uptime.
    func staticCPU(startingAt uptimeSeconds: Double = 0) -> ProbeStaticCPU {
        ProbeStaticCPU(pairs: staticPairs.filter { $0.startUptimeSeconds >= uptimeSeconds })
    }

    var wallSeconds: Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.uptimeSeconds - first.uptimeSeconds)
    }

    var cpuSeconds: Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.cpuSeconds - first.cpuSeconds)
    }

    var averageCPUPercent: Double {
        guard wallSeconds > 0 else { return 0 }
        return cpuSeconds / wallSeconds * 100
    }

    var peakResidentBytes: UInt64 {
        samples.map(\.residentBytes).max() ?? 0
    }

    var medianResidentBytes: UInt64 {
        let sorted = samples.map(\.residentBytes).sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    /// Seconds in which a one-second sample saw no delivered frame. With a 2 s capture
    /// interval about half of the samples are expected to be empty.
    var noFrameSeconds: Double {
        pairs.filter { $0.framesSeenDelta == 0 }.reduce(0) { $0 + $1.elapsedSeconds }
    }
}

/// Reads process usage and recorder counters once per second while capture runs.
actor ProbeSampler {
    private let recorder: Recorder
    private let printsProgress: Bool
    private let progressSeconds = 60.0
    private var samples: [ProbeSample] = []
    private var nextProgressSeconds = 60.0

    init(recorder: Recorder, printsProgress: Bool) {
        self.recorder = recorder
        self.printsProgress = printsProgress
    }

    func run(for duration: Duration) async {
        await takeSample()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: duration)
        while !Task.isCancelled, clock.now < deadline {
            try? await Task.sleep(for: .seconds(1))
            await takeSample()
            printProgressIfDue()
        }
    }

    /// Adds the reading that includes the recorder's final segment write.
    func finish() async {
        await takeSample()
    }

    func history() -> ProbeSampleHistory {
        ProbeSampleHistory(samples: samples)
    }

    private func takeSample() async {
        guard let usage = ProbeProcessUsage.read() else { return }
        let state = await recorder.currentState()
        samples.append(
            ProbeSample(
                uptimeSeconds: ProcessInfo.processInfo.systemUptime,
                cpuSeconds: usage.cpuSeconds,
                residentBytes: usage.residentBytes,
                framesSeen: state.framesSeen,
                framesKept: state.framesKept
            )
        )
    }

    private func printProgressIfDue() {
        guard printsProgress, let first = samples.first, let last = samples.last else { return }
        let elapsed = last.uptimeSeconds - first.uptimeSeconds
        guard elapsed >= nextProgressSeconds else { return }
        nextProgressSeconds += progressSeconds
        let cpu =
            elapsed > 0
            ? (last.cpuSeconds - first.cpuSeconds) / elapsed * 100
            : 0
        print(
            "[progress] elapsed=\(Int(elapsed))s seen=\(last.framesSeen) kept=\(last.framesKept) "
                + "cpu=\(String(format: "%.2f", cpu))% "
                + "rss=\(String(format: "%.1f", Double(last.residentBytes) / 1_000_000)) MB"
        )
    }
}
