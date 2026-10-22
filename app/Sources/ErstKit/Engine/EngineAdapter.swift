import ErstCore
import Foundation
import Synchronization
import os

private let engineAdapterLog = Logger(subsystem: "app.erst.Erst", category: "EngineAdapter")

/// Reports the first thumbnail that did not match its size, because every later frame would repeat it.
private final class InvalidThumbnailReport: Sendable {
    private let reported = Mutex(false)

    func report(width: Int, height: Int, lumaBytes: Int) {
        let isFirst = reported.withLock { reported -> Bool in
            defer { reported = true }
            return !reported
        }
        guard isFirst else { return }
        engineAdapterLog.error(
            "Thumbnail \(width, privacy: .public)x\(height, privacy: .public) carries \(lumaBytes, privacy: .public) luma bytes, so nothing was compared; this is a capture bug"
        )
    }
}

/// Bridges recorder values to the synchronous, thread-safe Rust engine without actor hops.
public struct EngineAdapter: KeepEvaluator, MemoryWriter, Sendable {
    private let engine: Engine
    private static let invalidThumbnail = InvalidThumbnailReport()

    /// Shares an already-open engine with the recorder.
    public init(engine: Engine) {
        self.engine = engine
    }

    public func evaluate(_ thumbnail: Thumbnail, at date: Date, focusChanged: Bool) -> KeepVerdict {
        let decision = engine.evaluateFrame(
            thumbnail: FfiThumbnail(
                width: UInt32(clamping: thumbnail.width),
                height: UInt32(clamping: thumbnail.height),
                luma: Data(thumbnail.luma)
            ),
            nowMs: Self.unixMilliseconds(date),
            focusChanged: focusChanged
        )
        if decision.reason == .invalidThumbnail {
            Self.invalidThumbnail.report(
                width: thumbnail.width, height: thumbnail.height, lumaBytes: thumbnail.luma.count)
        }
        return KeepVerdict(keep: decision.keep, changeRatio: decision.changeRatio)
    }

    public func beginSegment(
        relativePath: String, startedAt: Date, width: Int, height: Int
    ) throws -> Int64 {
        try engine.beginSegment(
            relativePath: relativePath,
            startedAtMs: Self.unixMilliseconds(startedAt),
            width: UInt32(clamping: width),
            height: UInt32(clamping: height)
        )
    }

    public func finishSegment(id: Int64, endedAt: Date, bytes: Int64) throws {
        try engine.finishSegment(
            segmentId: id,
            endedAtMs: Self.unixMilliseconds(endedAt),
            bytes: UInt64(clamping: bytes)
        )
    }

    public func recordFrame(_ frame: RecordedFrame) throws -> Int64 {
        try engine.recordFrame(
            frame: FfiNewFrame(
                capturedAtMs: Self.unixMilliseconds(frame.capturedAt),
                segmentId: frame.segmentID,
                ptsMs: frame.ptsMilliseconds,
                bundleId: frame.bundleID,
                appName: frame.appName,
                windowTitle: frame.windowTitle,
                url: frame.url?.absoluteString,
                changeRatio: frame.changeRatio,
                lines: frame.lines.map(Self.textLine)
            )
        )
    }

    public func beginSpan(
        bundleID: String, appName: String, windowTitle: String?, url: URL?, at date: Date
    ) throws -> Int64 {
        try engine.beginSpan(
            bundleId: bundleID,
            appName: appName,
            windowTitle: windowTitle,
            url: url?.absoluteString,
            startedAtMs: Self.unixMilliseconds(date)
        )
    }

    public func endSpan(id: Int64, at date: Date) throws {
        try engine.endSpan(spanId: id, endedAtMs: Self.unixMilliseconds(date))
    }

    private static func unixMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func textLine(_ line: RecognizedLine) -> FfiTextLine {
        // RecognizedLine is already top-left. Vision's Y flip happens only in TextRecognizer.
        let scale = 10_000.0
        func coordinate(_ value: CGFloat) -> UInt16 {
            UInt16((min(1, max(0, value.isFinite ? value : 0)) * scale).rounded())
        }
        let x = coordinate(line.box.minX)
        let y = coordinate(line.box.minY)
        return FfiTextLine(
            text: line.text, x: x, y: y,
            w: min(coordinate(line.box.width), 10_000 - x),
            h: min(coordinate(line.box.height), 10_000 - y),
            source: line.source == .accessibility ? .accessibility : .ocr
        )
    }
}
