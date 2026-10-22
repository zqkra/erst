import AVFoundation
import CoreGraphics
import Foundation

/// Wraps an image generator so its async calls can cross actor boundaries.
///
/// AVAssetImageGenerator keeps its own request state and is safe to drive from one
/// background task at a time; this box is only used by the FrameReader actor.
final class ImageGeneratorBox: @unchecked Sendable {
    private let generator: AVAssetImageGenerator
    /// The file size the asset loaded, so a segment that grew gets a new box.
    let fileSize: Int64?

    init(url: URL) {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        self.generator = generator
        fileSize = Self.fileSize(at: url)
    }

    /// Reads the file size with a local stat, cheap next to a decode.
    static func fileSize(at url: URL) -> Int64? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return Int64(size)
    }

    func setMaximumSize(_ size: CGSize) {
        generator.maximumSize = size
    }

    func image(at time: CMTime) async throws -> CGImage {
        try await generator.image(at: time).image
    }

    func cancel() {
        generator.cancelAllCGImageGeneration()
    }
}
