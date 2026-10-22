import Foundation

/// What the capture pipeline is doing right now.
public enum RecorderStatus: Hashable, Sendable {
    case recording
    case paused(until: Date?)
    case needsPermission
    case stopped
}
