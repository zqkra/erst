import ApplicationServices
import ErstCore
import ErstKit
import Foundation
import SQLite3

/// Prints the production measurement that docs/MEASUREMENTS.md records.
enum ProbeProductionSummary {
    static func printSummary(
        engine: Engine,
        recorder: Recorder,
        dataDirectory: URL,
        configuration: RecorderConfiguration,
        history: ProbeSampleHistory,
        timings: ProbeStageTimings,
        idleGateDisabled: Bool,
        recorderStartedUptime: Double
    ) async throws {
        let databaseFile = dataDirectory.appendingPathComponent("erst.sqlite")
        // The caller has stopped the recorder, so the writer is closed and the checkpoint
        // measures what stays on disk instead of a log the next write would have to replay.
        checkpoint(databaseFile)
        let metrics = await recorder.metrics()
        let (storage, timeline) = try await Task.detached {
            try (
                engine.storage(),
                engine.timeline(
                    startMs: 0,
                    endMs: Int64(Date().timeIntervalSince1970 * 1000) + 1,
                    buckets: 1
                )
            )
        }.value
        let stamps = timeline.stamps
        let framesWithText = try await Task.detached {
            var count = 0
            for stamp in stamps {
                let moment = try engine.moment(frameId: stamp.id, timeZone: "UTC")
                if !moment.lines.isEmpty { count += 1 }
            }
            return count
        }.value

        let databaseBytes = fileBytes(databaseFile)
        let walBytes = fileBytes(dataDirectory.appendingPathComponent("erst.sqlite-wal"))
        let totalBytes = storage.videoBytes + databaseBytes
        let wallSeconds = history.wallSeconds
        let hours = wallSeconds / 3600
        let bytesPerHour = hours > 0 ? Double(totalBytes) / hours : 0
        let eightHourBytes = bytesPerHour * 8
        let coverage =
            stamps.isEmpty ? 0 : Double(framesWithText) / Double(stamps.count) * 100

        print("")
        print("ErstProbe production summary")
        print("data directory: \(dataDirectory.path)")
        print("configuration: \(describe(configuration))")
        print("accessibility trusted: \(AXIsProcessTrusted() ? "yes" : "no")")
        if idleGateDisabled {
            print(
                "runtime override: idle gate disabled "
                    + "(\(Int(ProbeProductionConfiguration.disabledIdleThreshold)) s) "
                    + "by --no-idle-gate"
            )
        }
        print("wall time: \(decimal(wallSeconds, 1)) s (\(decimal(wallSeconds / 60, 1)) min)")
        print("frames seen: \(metrics.framesSeen)")
        print("frames kept: \(metrics.framesKept)")
        print("stored frames: \(stamps.count)")
        print(
            "OCR coverage: \(framesWithText) of \(stamps.count) kept frames with text "
                + "(\(decimal(coverage, 1))%)"
        )
        print("segments: \(storage.segmentCount)")
        print("total video bytes: \(megabytes(storage.videoBytes)) MB (\(storage.videoBytes) bytes)")
        print("database bytes: \(megabytes(databaseBytes)) MB (\(databaseBytes) bytes)")
        print("write-ahead log after checkpoint: \(walBytes) bytes")
        print("total bytes: \(megabytes(totalBytes)) MB")
        print(
            "average CPU: \(decimal(history.averageCPUPercent, 2))% of one core "
                + "(\(decimal(history.cpuSeconds, 1)) s CPU over \(decimal(wallSeconds, 1)) s)"
        )
        printStaticCPU(history, metrics: metrics, recorderStartedUptime: recorderStartedUptime)
        print("peak resident memory: \(megabytes(history.peakResidentBytes)) MB")
        print("median resident memory: \(megabytes(history.medianResidentBytes)) MB")
        print("bytes per hour of capture: \(megabytes(bytesPerHour)) MB")
        print("8-hour day estimate: \(megabytes(eightHourBytes)) MB")
        printStageTimings(timings, metrics: metrics)
    }

    private static func printStaticCPU(
        _ history: ProbeSampleHistory,
        metrics: RecorderMetrics,
        recorderStartedUptime: Double
    ) {
        let wholeRun = history.staticCPU()
        if let percent = wholeRun.percent {
            print(
                "static-screen CPU (whole run): \(decimal(percent, 2))% of one core over "
                    + "\(decimal(wholeRun.seconds, 1)) s "
                    + "(\(wholeRun.pairs.count) of \(history.pairs.count) sampled seconds had frames seen "
                    + "but none kept; upper bound because OCR may spill over from the last kept frame)"
            )
        } else {
            print(
                "static-screen CPU (whole run): unavailable "
                    + "(no sampled second had frames seen but none kept)"
            )
        }
        printStaticCPUAfterWarmUp(
            history, metrics: metrics, recorderStartedUptime: recorderStartedUptime)
        print(
            "empty one-second samples: \(decimal(history.noFrameSeconds, 1)) s "
                + "(no frame delivered; a 2 s capture interval leaves about half of them empty)"
        )
    }

    /// Leaves out the OCR warm-up, whose failed accurate request costs seconds of CPU that
    /// are not capture work. The warm-up time starts at recorder start.
    private static func printStaticCPUAfterWarmUp(
        _ history: ProbeSampleHistory,
        metrics: RecorderMetrics,
        recorderStartedUptime: Double
    ) {
        guard let warmUpMilliseconds = metrics.ocrWarmUpMilliseconds else {
            print("static-screen CPU after warm-up: unavailable (OCR warm-up did not finish)")
            return
        }
        let warmUpEndUptime = recorderStartedUptime + warmUpMilliseconds / 1000
        let afterWarmUp = history.staticCPU(startingAt: warmUpEndUptime)
        guard let percent = afterWarmUp.percent else {
            print(
                "static-screen CPU after warm-up: unavailable "
                    + "(no sampled second after warm-up had frames seen but none kept)"
            )
            return
        }
        print(
            "static-screen CPU after warm-up: \(decimal(percent, 2))% of one core over "
                + "\(decimal(afterWarmUp.seconds, 1)) s "
                + "(\(afterWarmUp.pairs.count) sampled seconds that start after warm-up, "
                + "which ended \(decimal(warmUpMilliseconds / 1000, 1)) s into the run)"
        )
    }

    /// Folds the write-ahead log into the database, so the size is what stays on disk.
    private static func checkpoint(_ database: URL) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return
        }
        defer { sqlite3_close(handle) }
        sqlite3_exec(handle, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
    }

    private static func printStageTimings(_ timings: ProbeStageTimings, metrics: RecorderMetrics) {
        let statistics = timings.statistics()
        print("evaluate_frame: \(describe(statistics.evaluate))")
        print("record_frame: \(describe(statistics.record))")
        print(
            "OCR: \(metrics.ocrJobs) jobs, \(decimal(metrics.averageOCRMilliseconds, 1)) ms average, "
                + "warm-up "
                + (metrics.ocrWarmUpMilliseconds.map { "\(decimal($0, 0)) ms" } ?? "did not finish")
        )
        print(
            "accessibility: \(metrics.accessibilityReads) reads, "
                + "\(decimal(metrics.averageAccessibilityMilliseconds, 1)) ms average, "
                + "\(decimal(metrics.averageAccessibilityLines, 1)) lines per read, "
                + "\(metrics.accessibilityTruncatedReads) truncated, "
                + "\(metrics.ocrLinesReplaced) OCR lines replaced"
        )
        print(
            "Recognition level: "
                + (TextRecognizer.usesFastFallback
                    ? "fast fallback (accurate failed on this host)"
                    : "accurate")
        )
        print(
            "thumbnail: \(decimal(metrics.averageThumbnailMilliseconds, 3)) ms average "
                + "over \(metrics.framesSeen) frames"
        )
    }

    private static func describe(_ configuration: RecorderConfiguration) -> String {
        "capture every \(decimal(configuration.captureInterval, 1)) s, "
            + "\(decimal(configuration.segmentDuration, 1)) s segments, "
            + "\(configuration.compression.rawValue) compression, "
            + "idle after \(decimal(configuration.idleThreshold, 1)) s, "
            + "\(configuration.excludedBundleIDs.count) excluded apps"
    }

    private static func describe(_ statistics: ProbeStageStatistics?) -> String {
        guard let statistics else { return "unavailable" }
        return "p50 \(decimal(statistics.p50Milliseconds, 3)) ms, "
            + "p95 \(decimal(statistics.p95Milliseconds, 3)) ms, "
            + "max \(decimal(statistics.maximumMilliseconds, 3)) ms "
            + "(\(statistics.count) calls)"
    }

    private static func fileBytes(_ url: URL) -> UInt64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize
        else { return 0 }
        return UInt64(max(0, size))
    }

    private static func decimal(_ value: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    private static func megabytes(_ bytes: UInt64) -> String {
        decimal(Double(bytes) / 1_000_000, 1)
    }

    private static func megabytes(_ bytes: Double) -> String {
        decimal(bytes / 1_000_000, 1)
    }
}
