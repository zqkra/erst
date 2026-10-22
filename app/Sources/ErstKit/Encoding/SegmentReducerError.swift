import Foundation

/// Errors raised while reducing a finished segment.
public enum SegmentReducerError: Error, LocalizedError, Equatable {
    /// The file has no video track.
    case missingVideoTrack
    /// The source dimensions are not usable.
    case invalidDimensions
    /// Decoding or reading failed.
    case readFailed(String)
    /// Encoding or writing failed.
    case writeFailed(String)
    /// vImage could not scale a frame.
    case scaleFailed(Int)
    /// The reduced file could not replace the original.
    case replaceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            "The segment has no video track."
        case .invalidDimensions:
            "The segment has invalid dimensions."
        case .readFailed(let message):
            "Reading the segment failed: \(message)"
        case .writeFailed(let message):
            "Writing the reduced segment failed: \(message)"
        case .scaleFailed(let code):
            "vImage scaling failed with \(code)."
        case .replaceFailed(let message):
            "Replacing the segment failed: \(message)"
        }
    }
}
