import Foundation

/// The result of appending one frame to a segment.
public struct AppendResult: Sendable, Equatable {
    /// The segment that now contains the frame.
    public let segment: SegmentHandle
    /// Presentation time inside the segment, in milliseconds.
    public let ptsMilliseconds: Int64
    /// A segment that was closed to make room for this frame, if any.
    public let rotatedFrom: FinishedSegment?

    /// Creates an append result.
    public init(
        segment: SegmentHandle,
        ptsMilliseconds: Int64,
        rotatedFrom: FinishedSegment? = nil
    ) {
        self.segment = segment
        self.ptsMilliseconds = ptsMilliseconds
        self.rotatedFrom = rotatedFrom
    }
}
