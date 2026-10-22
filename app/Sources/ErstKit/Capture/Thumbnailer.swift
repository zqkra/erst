import CoreVideo
import Foundation

/// Converts captured BGRA frames into fixed size luma thumbnails.
///
/// Every output pixel is the mean luma of a 2x2-strided grid of its source block, read
/// straight from the BGRA buffer with Rec. 709 integer weights. The previous vImage high
/// quality resample took about 20 ms per 2560x1440 frame. This path needs no full size
/// scratch image: one horizontal pass over the sampled rows, then one vertical pass. The
/// recorder feeds it one frame at a time, so the scratch buffers stay in a value type instead
/// of behind an actor hop.
public struct Thumbnailer: Sendable {
    private static let outputWidth = Thumbnail.standardWidth
    private static let outputHeight = Thumbnail.standardHeight
    /// Reads every second row and column of a block. 64 samples per 16x16 block keep the mean
    /// within one luma level of the full mean on screen content, and the diff threshold is 6
    /// levels.
    private static let sampleStride = 2
    // Rec. 709 luma weights scaled by 10000, in BGRA byte order. The same scale the vImage
    // matrix in the previous implementation used, so the diff sees the same luma values.
    private static let blueWeight: UInt32 = 722
    private static let greenWeight: UInt32 = 7152
    private static let redWeight: UInt32 = 2126
    private static let lumaScale: UInt32 = 10000

    /// Source column for each output column boundary, `outputWidth + 1` entries.
    private var columnStarts: [Int] = []
    /// Source row for each output row boundary, `outputHeight + 1` entries.
    private var rowStarts: [Int] = []
    /// Sampled source columns in each output column block, `outputWidth` entries.
    private var columnSamples: [Int] = []
    /// Sampled source rows in each output row block, `outputHeight` entries.
    private var rowSamples: [Int] = []
    /// Horizontal luma sums for every source row, `outputWidth * height` entries.
    private var rowSums: [UInt32] = []
    private var boundsWidth = -1
    private var boundsHeight = -1

    /// Creates a thumbnailer with reusable scratch buffers.
    public init() {}

    /// Scales the frame to 160 by 90 and converts it to Rec. 709 luma.
    public mutating func thumbnail(from pixelBuffer: CVPixelBuffer) throws -> Thumbnail {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA else {
            throw ThumbnailerError.unsupportedPixelFormat(format)
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { throw ThumbnailerError.missingBaseAddress }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw ThumbnailerError.missingBaseAddress
        }
        updateBounds(width: width, height: height)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width >= Self.outputWidth, height >= Self.outputHeight else {
            return Thumbnail(
                luma: Self.nearestLuma(
                    base: baseAddress, rowBytes: rowBytes, width: width, height: height))
        }
        return Thumbnail(luma: blockLuma(base: baseAddress, rowBytes: rowBytes))
    }

    /// Rebuilds the boundaries only when the frame size changes.
    private mutating func updateBounds(width: Int, height: Int) {
        guard width != boundsWidth || height != boundsHeight else { return }
        boundsWidth = width
        boundsHeight = height
        columnStarts = (0...Self.outputWidth).map { $0 * width / Self.outputWidth }
        rowStarts = (0...Self.outputHeight).map { $0 * height / Self.outputHeight }
        columnSamples = (0..<Self.outputWidth).map { x in
            (columnStarts[x + 1] - columnStarts[x] + Self.sampleStride - 1) / Self.sampleStride
        }
        rowSamples = (0..<Self.outputHeight).map { y in
            (rowStarts[y + 1] - rowStarts[y] + Self.sampleStride - 1) / Self.sampleStride
        }
        let required = Self.outputWidth * height
        if rowSums.count < required {
            rowSums = [UInt32](repeating: 0, count: required)
        }
    }

    /// Averages each source block: one horizontal pass over the sampled rows, one vertical
    /// pass over the sampled row sums.
    ///
    /// The horizontal pass accumulates the channels of a block in two 64-bit words with
    /// 16-bit lanes, blue and red in one and green and alpha in the other. A block is far
    /// narrower than 65536 pixels, so a lane cannot carry into its neighbour, and three
    /// multiplies per block replace three per pixel. Iterating per output row keeps the
    /// strided read inside the source rows the block covers, so half the rows are never touched.
    private mutating func blockLuma(
        base: UnsafeMutableRawPointer,
        rowBytes: Int
    ) -> [UInt8] {
        var luma = [UInt8](repeating: 0, count: Self.outputWidth * Self.outputHeight)
        let columns = columnStarts
        let rows = rowStarts
        let samplesX = columnSamples
        let samplesY = rowSamples
        rowSums.withUnsafeMutableBufferPointer { sums in
            columns.withUnsafeBufferPointer { startX in
                for y in 0..<Self.outputHeight {
                    for sourceY in stride(from: rows[y], to: rows[y + 1], by: Self.sampleStride) {
                        let pixels = (base + sourceY * rowBytes)
                            .assumingMemoryBound(to: UInt32.self)
                        let rowBase = sourceY * Self.outputWidth
                        for x in 0..<Self.outputWidth {
                            var blueAndRed: UInt64 = 0
                            var greenAndAlpha: UInt64 = 0
                            var sourceX = startX[x]
                            let end = startX[x + 1]
                            while sourceX < end {
                                let pixel = UInt64(pixels[sourceX])
                                blueAndRed &+= pixel & 0x00FF00FF
                                greenAndAlpha &+= (pixel >> 8) & 0x00FF00FF
                                sourceX += Self.sampleStride
                            }
                            let blue = blueAndRed & 0xFFFF
                            let red = (blueAndRed >> 16) & 0xFFFF
                            let green = greenAndAlpha & 0xFFFF
                            sums[rowBase + x] =
                                UInt32(blue) &* Self.blueWeight
                                &+ UInt32(green) &* Self.greenWeight
                                &+ UInt32(red) &* Self.redWeight
                        }
                    }
                }
            }
            luma.withUnsafeMutableBufferPointer { out in
                rows.withUnsafeBufferPointer { startY in
                    for y in 0..<Self.outputHeight {
                        let first = startY[y]
                        let last = startY[y + 1]
                        for x in 0..<Self.outputWidth {
                            var sum: UInt64 = 0
                            for sourceY in stride(from: first, to: last, by: Self.sampleStride) {
                                sum &+= UInt64(sums[sourceY * Self.outputWidth + x])
                            }
                            let count = samplesY[y] * samplesX[x]
                            let divisor = UInt64(count) * UInt64(Self.lumaScale)
                            out[y * Self.outputWidth + x] = UInt8((sum &+ divisor / 2) / divisor)
                        }
                    }
                }
            }
        }
        return luma
    }

    /// Picks one source pixel per output pixel for frames smaller than the thumbnail.
    private static func nearestLuma(
        base: UnsafeMutableRawPointer,
        rowBytes: Int,
        width: Int,
        height: Int
    ) -> [UInt8] {
        var luma = [UInt8](repeating: 0, count: outputWidth * outputHeight)
        for y in 0..<outputHeight {
            let sourceY = min(height - 1, y * height / outputHeight)
            let pixels = (base + sourceY * rowBytes).assumingMemoryBound(to: UInt32.self)
            for x in 0..<outputWidth {
                let sourceX = min(width - 1, x * width / outputWidth)
                luma[y * outputWidth + x] = UInt8(
                    (lumaValue(pixels[sourceX]) &+ lumaScale / 2) / lumaScale)
            }
        }
        return luma
    }

    /// Rec. 709 luma of one BGRA pixel, scaled by `lumaScale`.
    @inline(__always)
    private static func lumaValue(_ pixel: UInt32) -> UInt32 {
        let blue = pixel & 0xFF
        let green = (pixel >> 8) & 0xFF
        let red = (pixel >> 16) & 0xFF
        return blue &* blueWeight &+ green &* greenWeight &+ red &* redWeight
    }
}
