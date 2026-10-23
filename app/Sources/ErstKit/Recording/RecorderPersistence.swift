import CoreGraphics
import Foundation

extension Recorder {
    /// Flushes pending writes and closes the open segment before the next kept frame.
    public func finishOpenSegment() async {
        await acquirePipeline()
        defer { releasePipeline() }
        await ocrQueue.finishPending()
        memory.flushPending()
        do {
            if let finished = try await segmentWriter.finish() { memory.finishSegment(finished) }
        } catch {
            recorderLog.error("Finishing a segment failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops matching in-flight OCR and persistence jobs, and evicts matching cached images.
    public func discardPending(capturedIn range: ClosedRange<Date>) async {
        memory.discard(capturedIn: range)
        await ocrQueue.discardPending(capturedIn: range)
    }

    /// Returns a kept frame cached within the last 60 seconds, or one the open segment may not hold
    /// yet, at most 1280 pixels on its long side.
    public func recentFrame(id: Int64) -> CGImage? {
        memory.recentFrame(id: id)
    }

    /// Returns the newest persisted frame still present in the recent-image cache.
    public func latestFrame() -> (id: Int64, image: CGImage)? {
        memory.latestFrame()
    }

    func store(_ frame: QueuedFrame, ocr lines: [RecognizedLine], accessibility: AccessibilityReading) {
        accessibilityReads += 1
        accessibilityMilliseconds += accessibility.milliseconds
        accessibilityLines += accessibility.lines.count
        if accessibility.truncated { accessibilityTruncatedReads += 1 }
        let merged = TextMerge.merge(ocr: lines, accessibility: accessibility.lines)
        ocrLinesReplaced += merged.replaced
        // The engine call and the preview image allocation belong to this frame alone.
        autoreleasepool { memory.record(frame, lines: merged.lines) }
    }
}
