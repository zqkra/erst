import CoreGraphics
import Foundation

/// The app icon's thermal palette, sampled from the icon: no heat, deep red, coral, orange, and the
/// yellow core of its rings.
public enum HeatPalette {
    /// The color of no heat.
    public enum Ground: Sendable {
        /// The window ground, for art that is the background itself.
        case window
        /// Black, for art laid over another surface with additive blending.
        case black
    }

    private struct Stop {
        let position: CGFloat
        let rgb: UInt32
    }

    private static let windowGroundRGB: UInt32 = 0x0E0E0F
    private static let heatStops = [
        Stop(position: 0.18, rgb: 0x2A1715),
        Stop(position: 0.34, rgb: 0x72413A),
        Stop(position: 0.48, rgb: 0xC36557),
        Stop(position: 0.60, rgb: 0xD5745D),
        Stop(position: 0.74, rgb: 0xF4A263),
        Stop(position: 0.88, rgb: 0xFAC371),
        Stop(position: 1.00, rgb: 0xFCD27B),
    ]
    private static let gradientWidthPixels = 256

    /// A one-pixel-high strip from no heat on the left to full heat on the right, for Core Image's
    /// color map.
    @MainActor
    static func gradient(ground: Ground) -> CGImage? {
        switch ground {
        case .window: windowGradient
        case .black: blackGradient
        }
    }

    @MainActor private static let windowGradient = makeGradient(groundRGB: windowGroundRGB)
    @MainActor private static let blackGradient = makeGradient(groundRGB: 0)

    private static func makeGradient(groundRGB: UInt32) -> CGImage? {
        let stops = [Stop(position: 0, rgb: groundRGB)] + heatStops
        var bytes = [UInt8]()
        bytes.reserveCapacity(gradientWidthPixels * 4)
        for index in 0..<gradientWidthPixels {
            let position = CGFloat(index) / CGFloat(gradientWidthPixels - 1)
            let (red, green, blue) = color(at: position, stops: stops)
            bytes += [red, green, blue, 255]
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: gradientWidthPixels, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: gradientWidthPixels * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func color(at position: CGFloat, stops: [Stop]) -> (UInt8, UInt8, UInt8) {
        guard let upper = stops.firstIndex(where: { $0.position >= position }), upper > 0 else {
            return components(stops[0].rgb)
        }
        let low = stops[upper - 1]
        let high = stops[upper]
        let share = (position - low.position) / (high.position - low.position)
        let a = components(low.rgb)
        let b = components(high.rgb)
        func mix(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8((CGFloat(x) + (CGFloat(y) - CGFloat(x)) * share).rounded())
        }
        return (mix(a.0, b.0), mix(a.1, b.1), mix(a.2, b.2))
    }

    private static func components(_ rgb: UInt32) -> (UInt8, UInt8, UInt8) {
        (UInt8((rgb >> 16) & 0xFF), UInt8((rgb >> 8) & 0xFF), UInt8(rgb & 0xFF))
    }
}
