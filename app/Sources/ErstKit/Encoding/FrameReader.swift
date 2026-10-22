import AVFoundation
import CoreGraphics
import Foundation
import os

private let frameReaderLog = Logger(subsystem: "app.erst.Erst", category: "FrameReader")
private let generatorCacheLimit = 4

/// Decodes single frames from segments and keeps a small generator cache.
///
/// Segments are fragmented MP4 and the open one keeps growing, while an
/// `AVURLAsset` only sees the fragments that existed when it loaded. A cached
/// generator is therefore valid only for the file size it was made for, and a
/// failed read drops it so the next try loads the current file.
public actor FrameReader {
    private var generators: [URL: ImageGeneratorBox] = [:]
    private var usageOrder: [URL] = []

    /// Creates a frame reader with an empty cache.
    public init() {}

    /// Releases generators after video files have been erased or replaced.
    public func invalidate() {
        for generator in generators.values { generator.cancel() }
        generators.removeAll()
        usageOrder.removeAll()
    }

    /// Returns the frame nearest the presentation time, scaled below the pixel limit.
    public func image(
        for segmentURL: URL,
        ptsMilliseconds: Int64,
        maxPixelSize: Int
    ) async throws -> CGImage {
        let time = CMTime(value: ptsMilliseconds, timescale: 1000)
        let pixelLimit = max(32, maxPixelSize)
        do {
            return try await decode(segmentURL, at: time, maximumPixelSize: pixelLimit)
        } catch {
            // A generator that loaded while the segment was shorter cannot see later frames.
            evict(segmentURL)
            do {
                return try await decode(segmentURL, at: time, maximumPixelSize: pixelLimit)
            } catch {
                logFailure(error, url: segmentURL, ptsMilliseconds: ptsMilliseconds)
                throw error
            }
        }
    }

    private func decode(_ url: URL, at time: CMTime, maximumPixelSize: Int) async throws -> CGImage {
        let generator = generator(for: url)
        generator.setMaximumSize(CGSize(width: maximumPixelSize, height: maximumPixelSize))
        return try await generator.image(at: time)
    }

    private func logFailure(_ error: Error, url: URL, ptsMilliseconds: Int64) {
        let failure = error as NSError
        let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
        let detail =
            underlying.map { "\(failure.domain) \(failure.code), underlying \($0.domain) \($0.code)" }
            ?? "\(failure.domain) \(failure.code)"
        let message =
            "Reading \(url.lastPathComponent) at \(ptsMilliseconds) ms failed: "
            + "\(detail): \(failure.localizedDescription)"
        frameReaderLog.error("\(message, privacy: .public)")
    }

    private func generator(for url: URL) -> ImageGeneratorBox {
        let fileSize = ImageGeneratorBox.fileSize(at: url)
        if let cached = generators[url] {
            guard cached.fileSize == fileSize else {
                evict(url)
                return makeGenerator(for: url)
            }
            touch(url)
            return cached
        }
        return makeGenerator(for: url)
    }

    private func makeGenerator(for url: URL) -> ImageGeneratorBox {
        if generators.count >= generatorCacheLimit, let oldest = usageOrder.first {
            usageOrder.removeFirst()
            // Dropped, not cancelled: a read that is still running keeps the generator alive.
            generators.removeValue(forKey: oldest)
        }
        let generator = ImageGeneratorBox(url: url)
        generators[url] = generator
        usageOrder.append(url)
        return generator
    }

    /// Forgets a generator whose file grew or failed. Reads that still run on it finish; only
    /// `invalidate()`, after files were erased or rewritten, cancels them.
    private func evict(_ url: URL) {
        generators.removeValue(forKey: url)
        usageOrder.removeAll { $0 == url }
    }

    private func touch(_ url: URL) {
        guard let index = usageOrder.firstIndex(of: url) else { return }
        usageOrder.remove(at: index)
        usageOrder.append(url)
    }
}
