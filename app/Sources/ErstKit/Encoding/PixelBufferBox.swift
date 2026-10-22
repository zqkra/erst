import CoreVideo
import Foundation

/// Hands a captured pixel buffer to AVFoundation APIs that take a sending value.
///
/// A captured CVPixelBuffer is never mutated after capture, so sharing its reference
/// with the encoder is safe.
final class PixelBufferBox: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer

    init(_ pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }

    var readOnly: CVReadOnlyPixelBuffer {
        CVReadOnlyPixelBuffer(unsafeBuffer: pixelBuffer)
    }
}
