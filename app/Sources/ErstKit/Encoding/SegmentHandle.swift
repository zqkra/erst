import Foundation

/// Identifies one video segment on disk and in the database.
public struct SegmentHandle: Sendable, Equatable {
    /// Path relative to the data directory.
    public let relativePath: String
    /// When the segment started.
    public let startedAt: Date
    /// Encoded width in pixels.
    public let width: Int
    /// Encoded height in pixels.
    public let height: Int

    /// Creates a segment handle.
    public init(relativePath: String, startedAt: Date, width: Int, height: Int) {
        self.relativePath = relativePath
        self.startedAt = startedAt
        self.width = width
        self.height = height
    }
}
