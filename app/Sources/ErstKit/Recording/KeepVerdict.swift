import Foundation

/// The keep decision for one frame.
public struct KeepVerdict: Sendable, Equatable {
    /// Whether the frame should be stored.
    public let keep: Bool
    /// Fraction of the frame that changed, in the range 0 to 1.
    public let changeRatio: Float

    /// Creates a keep verdict.
    public init(keep: Bool, changeRatio: Float) {
        self.keep = keep
        self.changeRatio = changeRatio
    }
}
