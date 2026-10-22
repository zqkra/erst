import Foundation

/// A 160 by 90 luma image used for frame change detection.
public struct Thumbnail: Sendable, Equatable {
    /// Standard thumbnail width in pixels.
    public static let standardWidth = 160
    /// Standard thumbnail height in pixels.
    public static let standardHeight = 90

    /// Width in pixels.
    public let width: Int
    /// Height in pixels.
    public let height: Int
    /// Row major luma values, one byte per pixel.
    public let luma: [UInt8]

    /// Creates a thumbnail from row major luma bytes.
    public init(
        width: Int = Thumbnail.standardWidth,
        height: Int = Thumbnail.standardHeight,
        luma: [UInt8]
    ) {
        self.width = width
        self.height = height
        self.luma = luma
    }
}
