import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit
import Synchronization
import os

private let captureOutputLog = Logger(subsystem: "app.erst.Erst", category: "CaptureOutput")

/// Receives ScreenCaptureKit samples on its dedicated queue and forwards complete frames.
final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let source: Mutex<(displayID: CGDirectDisplayID, generation: UInt64)?>
    private let onFrame: @Sendable (CapturedFrame, UInt64) -> Void
    private let onStop: @Sendable (any Error) -> Void

    init(
        displayID: CGDirectDisplayID,
        generation: UInt64,
        onFrame: @escaping @Sendable (CapturedFrame, UInt64) -> Void,
        onStop: @escaping @Sendable (any Error) -> Void
    ) {
        self.source = Mutex((displayID, generation))
        self.onFrame = onFrame
        self.onStop = onStop
    }

    func setSource(_ value: (CGDirectDisplayID, UInt64)?) {
        source.withLock { $0 = value }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        // The sample handler runs on a long lived dispatch queue, so bridged sample attachments
        // would otherwise live until the next unrelated drain. Each frame gets its own pool.
        autoreleasepool {
            deliver(sampleBuffer, of: type)
        }
    }

    private func deliver(_ sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !FocusTracker.isSecureInputActive(),
            let source = source.withLock({ $0 })
        else { return }
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus),
            status == .complete
        else { return }
        // Anything that is not complete carries no new screen content. Dropping it here
        // keeps the static screen path free of pixel work, before the buffer is touched.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            captureOutputLog.error("Received a non-BGRA frame")
            return
        }
        let frame = CapturedFrame(
            pixelBuffer: pixelBuffer,
            capturedAt: Date(),
            displayID: source.displayID
        )
        onFrame(frame, source.generation)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop(error)
    }
}
