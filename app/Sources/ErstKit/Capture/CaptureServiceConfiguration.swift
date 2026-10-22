import Foundation

/// Capture settings used at startup and when updating the live stream.
public struct CaptureServiceConfiguration: Sendable {
    /// Seconds between captured frames. ScreenCaptureKit drops intermediate frames.
    public var captureInterval: TimeInterval
    /// Bundle identifiers whose windows are left out of the captured image.
    public var excludedBundleIDs: Set<String>

    /// Creates a capture configuration.
    public init(captureInterval: TimeInterval = 2, excludedBundleIDs: Set<String> = []) {
        self.captureInterval = max(0.1, captureInterval)
        self.excludedBundleIDs = excludedBundleIDs
    }
}
