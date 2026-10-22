import Foundation

/// Errors raised while writing an HEVC segment.
public enum SegmentWriterError: Error, LocalizedError, Equatable {
    /// The frame has no usable size.
    case invalidFrameSize
    /// The asset writer could not start.
    case startFailed(String)
    /// The encoder rejected a frame.
    case appendFailed(String)
    /// No segment is open.
    case notStarted

    public var errorDescription: String? {
        switch self {
        case .invalidFrameSize:
            "The frame has no usable size."
        case .startFailed(let message):
            "Starting the segment writer failed: \(message)"
        case .appendFailed(let message):
            "Appending a frame failed: \(message)"
        case .notStarted:
            "No segment is open."
        }
    }
}
