import Foundation

/// Tunable recorder settings.
public struct RecorderConfiguration: Sendable {
    /// Seconds between captured frames.
    public var captureInterval: TimeInterval
    /// Seconds before a segment rotates.
    public var segmentDuration: TimeInterval
    /// HEVC quality and speed tradeoff.
    public var compression: Compression
    /// Bundle identifiers that are never captured, stored, or tracked as spans.
    public var excludedBundleIDs: Set<String>
    /// Seconds without input before the recorder treats the user as idle.
    public var idleThreshold: TimeInterval

    /// Creates a recorder configuration.
    public init(
        captureInterval: TimeInterval = 2,
        segmentDuration: TimeInterval = 300,
        compression: Compression = .faster,
        excludedBundleIDs: Set<String> = [],
        idleThreshold: TimeInterval = 120
    ) {
        self.captureInterval = captureInterval
        self.segmentDuration = segmentDuration
        self.compression = compression
        self.excludedBundleIDs = excludedBundleIDs
        self.idleThreshold = idleThreshold
    }
}
