import CoreGraphics
import CoreVideo

/// A fingerprint of every 32 by 32 pixel tile of a frame.
///
/// Two frames compare tile by tile, so text recognition reads again only the tiles whose pixels
/// changed. Any changed byte changes its tile's fingerprint, so an unchanged tile holds exactly
/// the pixels, and so the text, it held before.
struct TileSignature: Sendable {
    static let tileSide = 32
    private static let seed: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3
    private static let bytesPerPixel = 4

    let width: Int
    let height: Int
    let columns: Int
    let rows: Int
    private let hashes: [UInt64]

    /// Fingerprints a 32-bit BGRA frame, or nil when its pixels cannot be read.
    init?(_ pixelBuffer: CVPixelBuffer) {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let columns = (width + Self.tileSide - 1) / Self.tileSide
        let rows = (height + Self.tileSide - 1) / Self.tileSide
        var hashes = [UInt64](repeating: Self.seed, count: columns * rows)
        hashes.withUnsafeMutableBufferPointer { tiles in
            for y in 0..<height {
                let row = UnsafeRawPointer(base.advanced(by: y * rowBytes))
                let tileRow = (y / Self.tileSide) * columns
                for column in 0..<columns {
                    let startByte = column * Self.tileSide * Self.bytesPerPixel
                    let byteCount = min(Self.tileSide, width - column * Self.tileSide) * Self.bytesPerPixel
                    tiles[tileRow + column] = Self.fold(
                        tiles[tileRow + column], row.advanced(by: startByte), byteCount: byteCount)
                }
            }
        }
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
        self.hashes = hashes
    }

    /// FNV-1a over 64-bit words, then the bytes left over.
    private static func fold(_ hash: UInt64, _ bytes: UnsafeRawPointer, byteCount: Int) -> UInt64 {
        var hash = hash
        let words = byteCount / MemoryLayout<UInt64>.size
        for index in 0..<words {
            let word = bytes.loadUnaligned(
                fromByteOffset: index * MemoryLayout<UInt64>.size, as: UInt64.self)
            hash = (hash ^ word) &* prime
        }
        for offset in (words * MemoryLayout<UInt64>.size)..<byteCount {
            hash = (hash ^ UInt64(bytes.load(fromByteOffset: offset, as: UInt8.self))) &* prime
        }
        return hash
    }

    /// The tiles whose pixels differ from `previous`, row by row, or nil when the frames differ in
    /// size and every tile counts as changed.
    func changedTiles(since previous: TileSignature) -> [Bool]? {
        guard width == previous.width, height == previous.height else { return nil }
        return zip(hashes, previous.hashes).map { $0 != $1 }
    }

    /// A tile's rectangle in normalized top-left coordinates.
    func rect(column: Int, row: Int) -> CGRect {
        let minX = column * Self.tileSide
        let minY = row * Self.tileSide
        return CGRect(
            x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(min(Self.tileSide, width - minX)) / CGFloat(width),
            height: CGFloat(min(Self.tileSide, height - minY)) / CGFloat(height))
    }
}
