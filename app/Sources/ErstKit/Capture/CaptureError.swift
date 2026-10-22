import Foundation

/// Errors raised while setting up or updating screen capture.
public enum CaptureError: Error, LocalizedError, Equatable {
    /// Screen recording permission is missing.
    case permissionDenied
    /// No display is available to capture.
    case noDisplay
    /// The service was already stopped.
    case stopped
    /// ScreenCaptureKit returned an error.
    case streamFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording permission is missing."
        case .noDisplay:
            "No display is available for capture."
        case .stopped:
            "The capture service is stopped."
        case .streamFailed(let message):
            "Screen capture failed: \(message)"
        }
    }
}
