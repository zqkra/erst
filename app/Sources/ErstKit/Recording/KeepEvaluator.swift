import Foundation

/// Decides whether a changed frame is worth keeping.
public protocol KeepEvaluator: Sendable {
    /// Evaluates a thumbnail against the previous kept frame.
    func evaluate(_ thumbnail: Thumbnail, at date: Date, focusChanged: Bool) -> KeepVerdict
}
