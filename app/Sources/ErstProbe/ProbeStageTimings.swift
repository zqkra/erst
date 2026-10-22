import ErstKit
import Foundation
import Synchronization

/// Nearest-rank statistics for one timed stage.
struct ProbeStageStatistics: Sendable {
    let count: Int
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double

    static func make(from samples: [Double]) -> ProbeStageStatistics? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let p50 = sorted[rank(0.50, of: sorted.count)]
        let p95 = sorted[rank(0.95, of: sorted.count)]
        return ProbeStageStatistics(
            count: sorted.count,
            p50Milliseconds: p50,
            p95Milliseconds: p95,
            maximumMilliseconds: sorted[sorted.count - 1]
        )
    }

    private static func rank(_ fraction: Double, of count: Int) -> Int {
        max(0, min(count - 1, Int(ceil(Double(count) * fraction)) - 1))
    }
}

/// Collects timings for the two engine calls that docs/HYGIENE.md budgets.
final class ProbeStageTimings: Sendable {
    private let evaluateMilliseconds = Mutex<[Double]>([])
    private let recordMilliseconds = Mutex<[Double]>([])

    func addEvaluation(_ duration: Duration) {
        evaluateMilliseconds.withLock { $0.append(Self.milliseconds(duration)) }
    }

    func addRecord(_ duration: Duration) {
        recordMilliseconds.withLock { $0.append(Self.milliseconds(duration)) }
    }

    func statistics() -> (evaluate: ProbeStageStatistics?, record: ProbeStageStatistics?) {
        (
            ProbeStageStatistics.make(from: evaluateMilliseconds.withLock { $0 }),
            ProbeStageStatistics.make(from: recordMilliseconds.withLock { $0 })
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}

/// Times `Engine.evaluateFrame` without changing what the recorder does, and
/// optionally records the thumbnail in a keep trace.
struct ProbeTimedKeepEvaluator: KeepEvaluator {
    let adapter: EngineAdapter
    let timings: ProbeStageTimings
    let trace: ProbeKeepTrace?

    init(adapter: EngineAdapter, timings: ProbeStageTimings, trace: ProbeKeepTrace? = nil) {
        self.adapter = adapter
        self.timings = timings
        self.trace = trace
    }

    func evaluate(_ thumbnail: Thumbnail, at date: Date, focusChanged: Bool) -> KeepVerdict {
        trace?.append(thumbnail, at: date, focusChanged: focusChanged)
        let start = ContinuousClock.now
        let verdict = adapter.evaluate(thumbnail, at: date, focusChanged: focusChanged)
        timings.addEvaluation(start.duration(to: ContinuousClock.now))
        return verdict
    }
}

/// Times `Engine.recordFrame` and forwards every other write unchanged.
struct ProbeTimedMemoryWriter: MemoryWriter {
    let adapter: EngineAdapter
    let timings: ProbeStageTimings

    func beginSegment(
        relativePath: String,
        startedAt: Date,
        width: Int,
        height: Int
    ) throws -> Int64 {
        try adapter.beginSegment(
            relativePath: relativePath, startedAt: startedAt, width: width, height: height)
    }

    func finishSegment(id: Int64, endedAt: Date, bytes: Int64) throws {
        try adapter.finishSegment(id: id, endedAt: endedAt, bytes: bytes)
    }

    func recordFrame(_ frame: RecordedFrame) throws -> Int64 {
        let start = ContinuousClock.now
        let id = try adapter.recordFrame(frame)
        timings.addRecord(start.duration(to: ContinuousClock.now))
        return id
    }

    func beginSpan(
        bundleID: String,
        appName: String,
        windowTitle: String?,
        url: URL?,
        at: Date
    ) throws -> Int64 {
        try adapter.beginSpan(
            bundleID: bundleID, appName: appName, windowTitle: windowTitle, url: url, at: at)
    }

    func endSpan(id: Int64, at: Date) throws {
        try adapter.endSpan(id: id, at: at)
    }
}
