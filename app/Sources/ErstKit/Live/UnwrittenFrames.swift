import AVFoundation
import ErstCore
import Foundation
import os

private let recoveryLog = Logger(subsystem: "app.erst.Erst", category: "Recovery")

/// A video writer keeps its newest frame until the next one arrives, so a run that crashed or
/// was killed leaves the newest frame of its open segment out of the file. When the engine
/// opens, this finds where each recovered file's video really ends and drops the frames past
/// it, so the timeline never lands on a blank moment.
enum UnwrittenFrames {
    /// Set once every finished segment of this history has been checked.
    private static let historyCheckedKey = "UnwrittenFramesHistoryChecked"

    /// Checks the segments this open recovered from an interrupted run.
    static func drop(from engine: Engine) async {
        await check(engine.recoveredSegments(), in: engine)
    }

    /// History recorded before interrupted runs were repaired may hold such frames in segments
    /// finished long ago. They are checked once, in the background.
    static func checkHistoryOnce(_ engine: Engine) async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: historyCheckedKey),
            let segments = try? engine.finishedSegmentVideos()
        else { return }
        await check(segments, in: engine)
        defaults.set(true, forKey: historyCheckedKey)
    }

    private static func check(_ segments: [FfiSegmentVideo], in engine: Engine) async {
        for segment in segments {
            let url = URL(filePath: segment.path)
            guard let end = await writtenEnd(of: url) else {
                recoveryLog.error(
                    "Could not read \(url.lastPathComponent, privacy: .public); its frames stay")
                continue
            }
            do {
                let dropped = try engine.dropUnwrittenFrames(
                    segmentId: segment.segmentId, writtenUntilMs: end)
                if dropped > 0 {
                    recoveryLog.notice(
                        "Dropped \(dropped) frames an interrupted run kept out of \(url.lastPathComponent, privacy: .public)"
                    )
                }
            } catch {
                recoveryLog.error(
                    "Dropping unwritten frames failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Where the file's video ends, in milliseconds: zero when there is no file or no video in it,
    /// and nil when the file cannot be read, so nothing is dropped on a guess.
    static func writtenEnd(of url: URL) async -> Int64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        do {
            let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return 0 }
            let range = try await track.load(.timeRange)
            guard range.end.isNumeric else { return nil }
            return Int64((range.end.seconds * millisecondsPerSecond).rounded(.down))
        } catch {
            return nil
        }
    }

    private static let millisecondsPerSecond = 1000.0
}
