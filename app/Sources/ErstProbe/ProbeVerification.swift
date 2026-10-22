import CoreGraphics
import CoreVideo
import Darwin
import ErstCore
import ErstKit
import Foundation

/// Exercises persistence and encoding without Screen Recording permission.
enum ProbeVerification {
    private enum Failure: Error {
        case check(String)
    }

    static func run() async throws {
        try await Task.detached { try await verify() }.value
    }

    private static func verify() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErstProbe-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = try Engine.open(dataDir: directory.path)
        let adapter = EngineAdapter(engine: engine)
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let thumbnail = Thumbnail(luma: [UInt8](repeating: 80, count: 160 * 90))
        try require(adapter.evaluate(thumbnail, at: date, focusChanged: false).keep, "First frame")
        try require(!adapter.evaluate(thumbnail, at: date, focusChanged: false).keep, "Unchanged frame")
        try require(adapter.evaluate(thumbnail, at: date, focusChanged: true).keep, "Focus change")

        let (first, storedID, lines) = try await verifyEncoding(
            directory: directory, adapter: adapter, date: date)
        try await verifyStorage(
            engine: engine, adapter: adapter, directory: directory, date: date,
            first: first, storedID: storedID, lines: lines)
        print(
            "ErstProbe verification passed: 3 frames, 3 unique lines, 1 span; boxes, errors, rotation, timestamps, decoding"
        )
    }

    private static func verifyEncoding(directory: URL, adapter: EngineAdapter, date: Date) async throws
        -> (AppendResult, Int64, [RecognizedLine])
    {
        let writer = SegmentWriter(dataDirectory: directory)
        let first = try await writer.append(frame(width: 160, height: 90, at: date, displayID: 1))
        let firstID = try begin(first.segment, adapter: adapter)
        let lines = [
            RecognizedLine(
                text: "Erst adapter verification", box: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)),
            RecognizedLine(text: "Clipped box", box: CGRect(x: -0.1, y: 0.9, width: 0.6, height: 0.5)),
        ]
        let spanID = try adapter.beginSpan(
            bundleID: "app.erst.probe", appName: "Probe", windowTitle: "Verification", url: nil, at: date)
        let storedID = try adapter.recordFrame(recorded(first, segmentID: firstID, at: date, lines: lines))
        let secondDate = date.addingTimeInterval(1.5)
        let second = try await writer.append(frame(width: 160, height: 90, at: secondDate, displayID: 2))
        try require(second.rotatedFrom == nil && second.segment == first.segment, "Same-size display switch")
        try require(second.ptsMilliseconds == 1500, "Capture presentation timestamp")
        _ = try adapter.recordFrame(recorded(second, segmentID: firstID, at: secondDate, lines: lines))

        let thirdDate = date.addingTimeInterval(3)
        let third = try await writer.append(frame(width: 320, height: 180, at: thirdDate, displayID: 2))
        guard let rotated = third.rotatedFrom else { throw Failure.check("Size change did not rotate") }
        try adapter.finishSegment(id: firstID, endedAt: rotated.endedAt, bytes: rotated.bytes)
        let thirdID = try begin(third.segment, adapter: adapter)
        _ = try adapter.recordFrame(recorded(third, segmentID: thirdID, at: thirdDate, lines: []))
        guard let finished = try await writer.finish() else { throw Failure.check("Segment did not finish") }
        try adapter.finishSegment(id: thirdID, endedAt: finished.endedAt, bytes: finished.bytes)
        try require(try await writer.finish() == nil, "Repeated finalization")
        let fourthDate = date.addingTimeInterval(4)
        let fourth = try await writer.append(frame(width: 320, height: 180, at: fourthDate, displayID: 2))
        try require(
            fourth.segment != third.segment && fourth.ptsMilliseconds == 0, "Segment after finalization")
        _ = try await writer.finish()
        try adapter.endSpan(id: spanID, at: fourthDate)
        return (first, storedID, lines)
    }

    private static func verifyStorage(
        engine: Engine, adapter: EngineAdapter, directory: URL, date: Date,
        first: AppendResult, storedID: Int64, lines: [RecognizedLine]
    ) async throws {
        let moment = try engine.moment(frameId: storedID, timeZone: "UTC")
        try require(moment.stamp.capturedAtMs == 1_700_000_000_123, "Unix milliseconds")
        try require(moment.lines.count == 2, "Stored OCR lines")
        try require(
            moment.lines[0]
                == FfiTextLine(
                    text: lines[0].text, x: 1000, y: 2000, w: 3000, h: 4000, source: .ocr),
            "Top-left box scaled once")
        try require(
            moment.lines[1]
                == FfiTextLine(
                    text: lines[1].text, x: 0, y: 9000, w: 6000, h: 1000, source: .ocr),
            "Clamped OCR box")
        do {
            _ = try adapter.recordFrame(recorded(first, segmentID: -1, at: date, lines: []))
            throw Failure.check("Engine error was not propagated")
        } catch is ErstError {
            // The missing segment must cross the adapter as the original engine error.
        }
        let image = try await FrameReader().image(
            for: directory.appendingPathComponent(first.segment.relativePath),
            ptsMilliseconds: 0, maxPixelSize: 80)
        try require(max(image.width, image.height) <= 80, "Finished segment decoding")
        let storage = try engine.storage()
        let timeline = try engine.timeline(startMs: 0, endMs: 1_800_000_000_000, buckets: 1)
        try require(
            storage.frameCount == 3 && storage.uniqueLineCount == 3, "Stored counts and text deduplication")
        try require(timeline.spans.count == 1, "Stored span")
    }

    static func begin(_ segment: SegmentHandle, adapter: EngineAdapter) throws -> Int64 {
        try adapter.beginSegment(
            relativePath: segment.relativePath, startedAt: segment.startedAt,
            width: segment.width, height: segment.height)
    }

    static func recorded(
        _ result: AppendResult, segmentID: Int64, at date: Date, lines: [RecognizedLine]
    ) -> RecordedFrame {
        RecordedFrame(
            capturedAt: date, segmentID: segmentID, ptsMilliseconds: result.ptsMilliseconds,
            bundleID: "app.erst.probe", appName: "Probe", windowTitle: "Verification", url: nil,
            changeRatio: 1, lines: lines)
    }

    static func frame(
        width: Int, height: Int, at date: Date, displayID: CGDirectDisplayID
    ) throws -> CapturedFrame {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        guard result == kCVReturnSuccess, let buffer else { throw Failure.check("Pixel buffer creation") }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw Failure.check("Pixel buffer storage")
        }
        memset(base, 80, CVPixelBufferGetBytesPerRow(buffer) * height)
        return CapturedFrame(pixelBuffer: buffer, capturedAt: date, displayID: displayID)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.check(message) }
    }
}
