import CoreGraphics
import CoreVideo
import Foundation

/// One complete screen frame delivered by ScreenCaptureKit.
public struct CapturedFrame: @unchecked Sendable {
    /// The BGRA pixel buffer owned by this frame.
    public let pixelBuffer: CVPixelBuffer
    /// Wall clock time at which the frame reached the capture callback.
    public let capturedAt: Date
    /// The display the frame came from.
    public let displayID: CGDirectDisplayID

    /// Creates a captured frame.
    ///
    /// The pixel buffer is immutable once handed to this type, so sharing it between
    /// the encoder and OCR is safe.
    public init(pixelBuffer: CVPixelBuffer, capturedAt: Date, displayID: CGDirectDisplayID) {
        self.pixelBuffer = pixelBuffer
        self.capturedAt = capturedAt
        self.displayID = displayID
    }
}
