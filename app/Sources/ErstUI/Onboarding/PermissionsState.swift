import Foundation

/// What Erst is allowed to read from the system.
public struct PermissionsState: Hashable, Sendable {
    public var screenRecording: Bool
    public var accessibility: Bool

    public init(screenRecording: Bool, accessibility: Bool) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }

    public var isComplete: Bool {
        screenRecording && accessibility
    }
}
