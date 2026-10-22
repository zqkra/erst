import CoreGraphics
import ErstCore
import ErstKit
import Foundation

/// Checks that a moment's segment path decodes through the service the app uses.
enum ProbeLiveImageVerification {
    private enum Failure: Error {
        case check(String)
    }

    private static let frameWidth = 160
    private static let frameHeight = 90
    private static let frameCount = 2
    private static let maxPixelSize = 640
    private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    static func run() async throws {
        try await Task.detached { try await verify() }.value
    }

    private static func verify() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErstProbe-image-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let momentIDs = try await record(in: directory)
        let service = LiveMemoryService(
            engine: try await LiveEngine.open(at: directory), dataDirectory: directory)
        for momentID in momentIDs {
            let image = try await service.image(for: momentID, maxPixelSize: maxPixelSize)
            try require(
                image.width == frameWidth && image.height == frameHeight,
                "Moment \(momentID) decoded at \(image.width)x\(image.height)"
            )
        }
        print("ErstProbe live image verification passed: moments decode through LiveMemoryService")
    }

    /// Writes one finished segment before the reading engine opens, so one writer is open at a time.
    private static func record(in directory: URL) async throws -> [Int64] {
        let adapter = EngineAdapter(engine: try Engine.open(dataDir: directory.path))
        let writer = SegmentWriter(dataDirectory: directory)
        var segmentID: Int64?
        var momentIDs: [Int64] = []
        for index in 0..<frameCount {
            let date = start.addingTimeInterval(TimeInterval(index))
            let result = try await writer.append(
                ProbeVerification.frame(width: frameWidth, height: frameHeight, at: date, displayID: 1))
            if segmentID == nil {
                segmentID = try ProbeVerification.begin(result.segment, adapter: adapter)
            }
            guard let segmentID else { throw Failure.check("Segment did not begin") }
            momentIDs.append(
                try adapter.recordFrame(
                    ProbeVerification.recorded(result, segmentID: segmentID, at: date, lines: [])))
        }
        guard let finished = try await writer.finish(), let segmentID else {
            throw Failure.check("Segment did not finish")
        }
        try adapter.finishSegment(
            id: segmentID, endedAt: finished.endedAt, bytes: finished.bytes)
        return momentIDs
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.check(message) }
    }
}
