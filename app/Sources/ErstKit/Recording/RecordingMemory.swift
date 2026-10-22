import CoreGraphics
import Foundation
import os

private let recordingMemoryLog = Logger(subsystem: "app.erst.Erst", category: "RecordingMemory")

/// Tracks pending writes so discarded OCR completions cannot recreate erased frames.
struct RecordingMemory {
    private let writer: any MemoryWriter
    private var segmentIDs: [String: Int64] = [:]
    private var pending: [UInt64: Date] = [:]
    private var queuedFrames: [UInt64: QueuedFrame] = [:]
    private var recentFrames = RecentFrames()

    init(writer: any MemoryWriter) {
        self.writer = writer
    }

    mutating func register(id: UInt64, capturedAt: Date) {
        pending[id] = capturedAt
    }

    func contains(id: UInt64) -> Bool {
        pending[id] != nil
    }

    mutating func remove(id: UInt64) {
        pending.removeValue(forKey: id)
        queuedFrames.removeValue(forKey: id)
    }

    mutating func markQueued(_ frame: QueuedFrame) {
        queuedFrames[frame.id] = frame
    }

    mutating func flushPending() {
        // OCR completions may already be awaiting the recorder after leaving the OCR actor.
        for frame in queuedFrames.values.sorted(by: { $0.id < $1.id }) {
            record(frame, lines: [])
        }
    }

    mutating func discard(capturedIn range: ClosedRange<Date>) {
        pending = pending.filter { !range.contains($0.value) }
        queuedFrames = queuedFrames.filter { !range.contains($0.value.frame.capturedAt) }
        recentFrames.discard(capturedIn: range)
    }

    mutating func recentFrame(id: Int64) -> CGImage? {
        recentFrames.image(id: id)
    }

    mutating func latestFrame() -> (id: Int64, image: CGImage)? {
        recentFrames.latest()
    }

    mutating func record(_ queued: QueuedFrame, lines: [RecognizedLine]) {
        queuedFrames.removeValue(forKey: queued.id)
        guard pending.removeValue(forKey: queued.id) != nil else { return }
        let frame = RecordedFrame(
            capturedAt: queued.frame.capturedAt,
            segmentID: queued.segmentID,
            ptsMilliseconds: queued.ptsMilliseconds,
            bundleID: queued.focus.bundleID,
            appName: queued.focus.appName,
            windowTitle: queued.focus.windowTitle,
            url: queued.focus.url,
            changeRatio: queued.changeRatio,
            lines: lines
        )
        do {
            let id = try writer.recordFrame(frame)
            recentFrames.insert(id: id, frame: queued.frame)
        } catch {
            recordingMemoryLog.error(
                "Storing a frame failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    mutating func segmentID(for handle: SegmentHandle) -> Int64? {
        if let existing = segmentIDs[handle.relativePath] { return existing }
        do {
            let id = try writer.beginSegment(
                relativePath: handle.relativePath, startedAt: handle.startedAt,
                width: handle.width, height: handle.height
            )
            segmentIDs[handle.relativePath] = id
            return id
        } catch {
            recordingMemoryLog.error(
                "Starting a segment failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    mutating func finishSegment(_ finished: FinishedSegment) {
        guard let id = segmentIDs[finished.handle.relativePath] else { return }
        do {
            try writer.finishSegment(id: id, endedAt: finished.endedAt, bytes: finished.bytes)
            segmentIDs.removeValue(forKey: finished.handle.relativePath)
        } catch {
            recordingMemoryLog.error(
                "Finishing a segment failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
