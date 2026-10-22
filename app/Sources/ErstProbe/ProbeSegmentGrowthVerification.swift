import ErstKit
import Foundation

/// Checks that a segment which grew after a read decodes its new frames.
enum ProbeSegmentGrowthVerification {
    private enum Failure: Error {
        case check(String)
    }

    private static let frameWidth = 160
    private static let frameHeight = 90
    private static let shortFrameCount = 3
    private static let longFrameCount = 6
    private static let shortFrameMilliseconds: Int64 = 1000
    private static let grownFrameMilliseconds: Int64 = 4000
    private static let maxPixelSize = 80
    /// Capture appends a frame every second or more; the encoder rejects a burst of them.
    private static let appendPauseMilliseconds = 500

    static func run() async throws {
        try await Task.detached { try await verify() }.value
    }

    private static func verify() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErstProbe-growth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let growing = directory.appendingPathComponent("growing.mp4")
        let reader = FrameReader()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        _ = try await writeSegment(
            into: directory, frameCount: shortFrameCount, start: start, copyTo: growing)
        let short = try await reader.image(
            for: growing, ptsMilliseconds: shortFrameMilliseconds, maxPixelSize: maxPixelSize)
        try require(max(short.width, short.height) <= maxPixelSize, "Finished short segment decoding")

        _ = try await writeSegment(
            into: directory, frameCount: longFrameCount, start: start, copyTo: growing)
        do {
            _ = try await reader.image(
                for: growing, ptsMilliseconds: grownFrameMilliseconds, maxPixelSize: maxPixelSize)
        } catch {
            throw Failure.check(
                "A grown segment did not read its frame at \(grownFrameMilliseconds) ms: \(error)")
        }
        print("ErstProbe segment growth verification passed: a grown segment reads its new frames")
    }

    private static func writeSegment(
        into directory: URL, frameCount: Int, start: Date, copyTo destination: URL
    ) async throws {
        let writer = SegmentWriter(dataDirectory: directory)
        for index in 0..<frameCount {
            let date = start.addingTimeInterval(TimeInterval(index))
            _ = try await writer.append(
                ProbeVerification.frame(width: frameWidth, height: frameHeight, at: date, displayID: 1))
            try await Task.sleep(for: .milliseconds(appendPauseMilliseconds))
        }
        guard let finished = try await writer.finish() else {
            throw Failure.check("Segment did not finish")
        }
        let source = directory.appendingPathComponent(finished.handle.relativePath)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.check(message) }
    }
}
