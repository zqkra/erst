import Accelerate
import Compression
import CoreGraphics
import CoreVideo
import Foundation

/// Owns small independent images rather than retaining ScreenCaptureKit's pixel-buffer pool.
///
/// Each preview is kept LZ4-compressed, bit for bit, and decompressed only when a surface asks
/// for it. Screen content shrinks about 5.7 times (3.6 MB to 627 KB at 1280 px) for 1.2 ms of
/// CPU, and comes back in 0.4 ms.
struct RecentFrames {
    private static let lifetimeSeconds: TimeInterval = 60
    private static let maximumCount = 30
    /// Video compresses little, so the cap still holds about eight full frames, more than the
    /// ten seconds a segment needs before its newest frames can be read from the file.
    private static let maximumBytes = 24 * 1024 * 1024
    private static let maximumPixelSize: CGFloat = 1280
    private var entries: [(id: Int64, capturedAt: Date, preview: Preview)] = []

    mutating func insert(id: Int64, frame: CapturedFrame) {
        prune()
        guard frame.capturedAt >= Date().addingTimeInterval(-Self.lifetimeSeconds) else { return }
        guard let preview = Self.preview(from: frame.pixelBuffer) else { return }
        entries.append((id, frame.capturedAt, preview))
        var bytes = entries.reduce(0) { $0 + $1.preview.storedBytes }
        while entries.count > Self.maximumCount || bytes > Self.maximumBytes {
            bytes -= entries.removeFirst().preview.storedBytes
        }
    }

    mutating func image(id: Int64) -> CGImage? {
        prune()
        return entries.first { $0.id == id }?.preview.image()
    }

    mutating func latest() -> (id: Int64, image: CGImage)? {
        prune()
        guard let last = entries.last, let image = last.preview.image() else { return nil }
        return (last.id, image)
    }

    mutating func discard(capturedIn range: ClosedRange<Date>) {
        entries.removeAll { range.contains($0.capturedAt) }
    }

    private mutating func prune() {
        let oldest = Date().addingTimeInterval(-Self.lifetimeSeconds)
        entries.removeAll { $0.capturedAt < oldest }
    }

    /// Scales one frame to preview size with vImage and compresses the pixels.
    ///
    /// The previous Core Image path kept a render context and a 1280x720 IOSurface render
    /// target alive for every cached frame. `vImageCreateCGImageFromBuffer` would avoid the
    /// copy below, but on this SDK it never called the release callback, so a frame that left
    /// the cache kept its 3.7 MB of pixels and the recorder grew by that much per kept frame.
    private static func preview(from pixelBuffer: CVPixelBuffer) -> Preview? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 1, height > 1 else { return nil }
        let scale = min(1, maximumPixelSize / CGFloat(max(width, height)))
        let outputWidth = max(1, Int((CGFloat(width) * scale).rounded()))
        let outputHeight = max(1, Int((CGFloat(height) * scale).rounded()))
        let rowBytes = outputWidth * 4
        guard
            let context = CGContext(
                data: nil,
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.noneSkipFirst.rawValue
            ),
            let destinationStorage = context.data
        else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        var source = vImage_Buffer(
            data: baseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer)
        )
        var destination = vImage_Buffer(
            data: destinationStorage,
            height: vImagePixelCount(outputHeight),
            width: vImagePixelCount(outputWidth),
            rowBytes: rowBytes
        )
        let result = vImageScale_ARGB8888(
            &source,
            &destination,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )
        guard result == kvImageNoError else { return nil }
        return Preview(
            pixels: UnsafeRawBufferPointer(start: destinationStorage, count: rowBytes * outputHeight),
            width: outputWidth, height: outputHeight)
    }
}

/// One preview's BGRA pixels, LZ4-compressed when that makes them smaller.
private struct Preview {
    let width: Int
    let height: Int
    private let payload: Data
    private let isCompressed: Bool

    var storedBytes: Int { payload.count }
    private var rowBytes: Int { width * 4 }

    /// Copies out only the compressed bytes, so the preview holds no slack. Pixels LZ4 cannot
    /// shrink are kept as they are.
    init(pixels: UnsafeRawBufferPointer, width: Int, height: Int) {
        self.width = width
        self.height = height
        let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: pixels.count)
        defer { scratch.deallocate() }
        let source = pixels.bindMemory(to: UInt8.self)
        let size =
            source.baseAddress.map {
                compression_encode_buffer(scratch, pixels.count, $0, pixels.count, nil, COMPRESSION_LZ4)
            } ?? 0
        isCompressed = size > 0
        payload = isCompressed ? Data(bytes: scratch, count: size) : Data(pixels)
    }

    /// The pixels as an image, decompressed into memory the image owns.
    func image() -> CGImage? {
        let byteCount = rowBytes * height
        let pixels: Data
        if isCompressed {
            var restored = Data(count: byteCount)
            let size = restored.withUnsafeMutableBytes { destination in
                payload.withUnsafeBytes { source in
                    guard let target = destination.bindMemory(to: UInt8.self).baseAddress,
                        let compressed = source.bindMemory(to: UInt8.self).baseAddress
                    else { return 0 }
                    return compression_decode_buffer(
                        target, byteCount, compressed, payload.count, nil, COMPRESSION_LZ4)
                }
            }
            guard size == byteCount else { return nil }
            pixels = restored
        } else {
            pixels = payload
        }
        guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
