import Foundation

/// A segment that has been closed and written to disk.
public struct FinishedSegment: Sendable, Equatable {
    /// The segment that was closed.
    public let handle: SegmentHandle
    /// When the segment ended.
    public let endedAt: Date
    /// File size in bytes.
    public let bytes: Int64

    /// Creates a finished segment.
    public init(handle: SegmentHandle, endedAt: Date, bytes: Int64) {
        self.handle = handle
        self.endedAt = endedAt
        self.bytes = bytes
    }
}
