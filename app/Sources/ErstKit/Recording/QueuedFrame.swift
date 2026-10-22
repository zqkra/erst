import Foundation

/// A kept frame waiting for text recognition and storage.
struct QueuedFrame: Sendable {
    let id: UInt64
    let frame: CapturedFrame
    let segmentID: Int64
    let ptsMilliseconds: Int64
    let focus: FocusContext
    let changeRatio: Float
}
