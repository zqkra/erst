import Foundation

/// How aggressively the HEVC encoder trades file size for quality.
public enum Compression: String, Sendable, CaseIterable {
    /// Faster encoding with larger files.
    case faster
    /// Smaller files with slower encoding.
    case smaller

    /// The AVVideoQualityKey value for this setting.
    public var qualityValue: Float {
        switch self {
        case .faster: 0.6
        case .smaller: 0.45
        }
    }
}
