import Foundation

/// Persists segments, frames, text lines, and activity spans.
public protocol MemoryWriter: Sendable {
    /// Starts a segment row and returns its database id.
    func beginSegment(
        relativePath: String,
        startedAt: Date,
        width: Int,
        height: Int
    ) throws -> Int64
    /// Closes a segment row with its final size.
    func finishSegment(id: Int64, endedAt: Date, bytes: Int64) throws
    /// Stores one frame, its focus metadata, and its text lines.
    func recordFrame(_ frame: RecordedFrame) throws -> Int64
    /// Starts an activity span and returns its database id.
    func beginSpan(
        bundleID: String,
        appName: String,
        windowTitle: String?,
        url: URL?,
        at: Date
    ) throws -> Int64
    /// Closes an activity span.
    func endSpan(id: Int64, at: Date) throws
}
