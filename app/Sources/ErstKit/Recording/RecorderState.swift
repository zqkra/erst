import Foundation

/// A snapshot of the recorder counters published to the UI.
public struct RecorderState: Sendable, Equatable {
    /// The lifecycle state of a recorder.
    public enum Status: Sendable, Equatable {
        /// Capturing and keeping frames.
        case recording
        /// Not keeping frames until the given date, or until resumed when nil.
        case paused(until: Date?)
        /// Screen recording permission is missing.
        case needsPermission
        /// Stopped and finished.
        case stopped
    }

    /// Current lifecycle state.
    public let status: Status
    /// Frames delivered by capture since start.
    public let framesSeen: Int
    /// Frames kept by the evaluator since start.
    public let framesKept: Int
    /// When the last frame was kept, if any.
    public let lastKeptAt: Date?

    /// Creates a recorder state snapshot.
    public init(
        status: Status,
        framesSeen: Int,
        framesKept: Int,
        lastKeptAt: Date?
    ) {
        self.status = status
        self.framesSeen = framesSeen
        self.framesKept = framesKept
        self.lastKeptAt = lastKeptAt
    }
}
