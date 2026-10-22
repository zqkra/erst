import AVFoundation
import Accelerate
import CoreMedia
import CoreVideo
import Foundation
import os

private let segmentReducerLog = Logger(subsystem: "app.erst.Erst", category: "SegmentReducer")

/// Re-encodes a finished segment at half resolution and replaces it in place.
public struct SegmentReducer: Sendable {
    /// Creates a reducer.
    public init() {}

    /// Rewrites the segment at half size with the smaller compression and returns its byte size.
    public func reduce(_ segmentURL: URL) async throws -> Int64 {
        let asset = AVURLAsset(url: segmentURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw SegmentReducerError.missingVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let width = Int(naturalSize.width) / 2 & ~1
        let height = Int(naturalSize.height) / 2 & ~1
        guard width >= 2, height >= 2 else {
            throw SegmentReducerError.invalidDimensions
        }

        let tempURL =
            segmentURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(segmentURL.deletingPathExtension().lastPathComponent)"
                    + "-reduce-\(UUID().uuidString).mp4"
            )
        var replaced = false
        defer {
            if !replaced {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        let provider = reader.outputProvider(for: trackOutput)
        try reader.start()

        let (writer, input) = try makeWriter(url: tempURL, width: width, height: height)
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
        try writer.start()
        writer.startSession(atSourceTime: .zero)

        var attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
            size: CVImageSize(width: width, height: height)
        )
        attributes.backing = .ioSurface

        while let sample = try await provider.next() {
            try Task.checkCancellation()
            let pts = sample.presentationTimeStamp
            let scaled = try sample.withUnsafeSampleBuffer {
                (sampleBuffer: CMSampleBuffer) throws -> sending CVReadOnlyPixelBuffer? in
                guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
                return try Self.scale(source, width: width, height: height, attributes: attributes)
            }
            guard let scaled else { continue }
            guard try receiver.appendImmediately(scaled, with: pts) else {
                throw SegmentReducerError.writeFailed(
                    writer.error?.localizedDescription ?? "The writer rejected a frame."
                )
            }
        }
        if reader.status == .failed {
            throw SegmentReducerError.readFailed(
                reader.error?.localizedDescription ?? "The reader failed."
            )
        }

        receiver.finish()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw SegmentReducerError.writeFailed(
                writer.error?.localizedDescription ?? "The writer did not complete."
            )
        }

        do {
            _ = try FileManager.default.replaceItemAt(segmentURL, withItemAt: tempURL)
        } catch {
            throw SegmentReducerError.replaceFailed(error.localizedDescription)
        }
        replaced = true

        let values = try segmentURL.resourceValues(forKeys: [.fileSizeKey])
        let bytes = Int64(values.fileSize ?? 0)
        let message = "Reduced \(segmentURL.lastPathComponent) to \(bytes) bytes"
        segmentReducerLog.notice("\(message, privacy: .public)")
        return bytes
    }

    private func makeWriter(
        url: URL,
        width: Int,
        height: Int
    ) throws -> (writer: AVAssetWriter, input: AVAssetWriterInput) {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings = HEVCSettings.outputSettings(
            width: width,
            height: height,
            compression: .smaller
        )
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        return (writer, input)
    }

    private static func scale(
        _ source: CVPixelBuffer,
        width: Int,
        height: Int,
        attributes: CVPixelBufferCreationAttributes
    ) throws -> CVReadOnlyPixelBuffer? {
        let destination = try CVMutablePixelBuffer(attributes)
        try destination.withUnsafeBuffer { destinationBuffer in
            CVPixelBufferLockBaseAddress(source, .readOnly)
            CVPixelBufferLockBaseAddress(destinationBuffer, [])
            defer {
                CVPixelBufferUnlockBaseAddress(destinationBuffer, [])
                CVPixelBufferUnlockBaseAddress(source, .readOnly)
            }
            guard let sourceBase = CVPixelBufferGetBaseAddress(source),
                let destinationBase = CVPixelBufferGetBaseAddress(destinationBuffer)
            else { return }
            var sourceImage = vImage_Buffer(
                data: sourceBase,
                height: vImagePixelCount(CVPixelBufferGetHeight(source)),
                width: vImagePixelCount(CVPixelBufferGetWidth(source)),
                rowBytes: CVPixelBufferGetBytesPerRow(source)
            )
            var destinationImage = vImage_Buffer(
                data: destinationBase,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: CVPixelBufferGetBytesPerRow(destinationBuffer)
            )
            let result = vImageScale_ARGB8888(
                &sourceImage,
                &destinationImage,
                nil,
                vImage_Flags(kvImageHighQualityResampling)
            )
            guard result == kvImageNoError else {
                throw SegmentReducerError.scaleFailed(Int(result))
            }
        }
        return CVReadOnlyPixelBuffer(destination)
    }
}
