import CoreVideo
import Foundation

extension CapturedFrame {
    /// The same frame in a pixel buffer Erst owns.
    ///
    /// ScreenCaptureKit lends a stream only `queueDepth` buffers and stops delivering frames while
    /// all of them are held. Text recognition can hold its frame for seconds, and for good when
    /// Vision gets stuck inside macOS, so it reads a copy and the lent buffer goes back as soon as
    /// the encoder is done with it. When the copy cannot be made, the lent buffer is used.
    func owningCopy() -> CapturedFrame {
        guard let copy = Self.copy(of: pixelBuffer) else { return self }
        return CapturedFrame(pixelBuffer: copy, capturedAt: capturedAt, displayID: displayID)
    }

    private static func copy(of source: CVPixelBuffer) -> CVPixelBuffer? {
        let format = CVPixelBufferGetPixelFormatType(source)
        guard format == kCVPixelFormatType_32BGRA else { return nil }
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        // Backed by an IOSurface like the lent buffer, so Vision reads it the same way.
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        var created: CVPixelBuffer?
        guard
            CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attributes, &created)
                == kCVReturnSuccess,
            let copy = created
        else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        CVPixelBufferLockBaseAddress(copy, [])
        defer { CVPixelBufferUnlockBaseAddress(copy, []) }
        guard let from = CVPixelBufferGetBaseAddress(source), let to = CVPixelBufferGetBaseAddress(copy)
        else { return nil }
        let fromRowBytes = CVPixelBufferGetBytesPerRow(source)
        let toRowBytes = CVPixelBufferGetBytesPerRow(copy)
        let rowBytes = min(fromRowBytes, toRowBytes)
        for row in 0..<height {
            memcpy(to + row * toRowBytes, from + row * fromRowBytes, rowBytes)
        }
        // Color space and gamma travel with the pixels, so text and previews read the same.
        CVBufferPropagateAttachments(source, copy)
        return copy
    }
}
