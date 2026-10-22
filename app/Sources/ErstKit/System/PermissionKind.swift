import Foundation

/// A privacy permission Erst needs from the user.
public enum PermissionKind: String, Sendable, CaseIterable {
    /// Recording the screen and system audio.
    case screenRecording
    /// Reading window titles and browser URLs through the Accessibility API.
    case accessibility

    /// Human readable name used in logs and settings links.
    public var displayName: String {
        switch self {
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        }
    }
}
