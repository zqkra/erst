import ErstKit
import Foundation
import Synchronization

/// Collects exact per-job timings without polling recorder totals or timing database writes.
final class ProbeOCRMeasurements: Sendable {
    private let samples = Mutex<[Double]>([])
    private let printsJobs: Bool

    init(printsJobs: Bool = true) {
        self.printsJobs = printsJobs
    }

    func record(_ measurement: OCRMeasurement) {
        samples.withLock { $0.append(measurement.milliseconds) }
        guard printsJobs else { return }
        print(
            "[OCR] at=\(measurement.capturedAt.formatted(.iso8601)) "
                + "lines=\(measurement.lineCount) time=\(String(format: "%.1f", measurement.milliseconds)) ms"
        )
    }

    func printSummary() {
        let sorted = samples.withLock { $0.sorted() }
        guard !sorted.isEmpty else {
            print("p50 OCR time: unavailable (no completed jobs)")
            print("p95 OCR time: unavailable (no completed jobs)")
            return
        }
        // Nearest-rank percentiles retain the slowest sample in short probe runs.
        for (name, fraction) in [("p50", 0.50), ("p95", 0.95)] {
            let index = max(0, Int(ceil(Double(sorted.count) * fraction)) - 1)
            print("\(name) OCR time: \(String(format: "%.1f", sorted[index])) ms")
        }
    }
}
