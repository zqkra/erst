import Foundation

/// The current privacy permission snapshot.
public struct PermissionState: Sendable, Equatable {
    /// Whether screen recording is granted.
    public let screenRecording: Bool
    /// Whether Accessibility is granted.
    public let accessibility: Bool

    /// Creates a permission snapshot.
    public init(screenRecording: Bool, accessibility: Bool) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }

    /// Whether the given permission is granted.
    public func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .screenRecording: screenRecording
        case .accessibility: accessibility
        }
    }
}
