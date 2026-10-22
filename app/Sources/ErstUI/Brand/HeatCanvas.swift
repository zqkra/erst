import CoreGraphics
import CoreImage

/// One line of heat: where it runs, how wide it is, and how hot it is, from 0 to 1.
public struct HeatStroke: @unchecked Sendable {
    public let path: CGPath
    public let width: CGFloat
    public let heat: CGFloat
    public let cap: CGLineCap

    public init(path: CGPath, width: CGFloat, heat: CGFloat, cap: CGLineCap = .round) {
        self.path = path
        self.width = width
        self.heat = heat
        self.cap = cap
    }
}

/// How a heat picture develops, the way the app icon was made: the strokes diffuse like heat,
/// take a camera's grain, and map through the icon's thermal palette.
public struct HeatDevelopment: Sendable {
    /// The diffusion, as the blur's standard deviation in points.
    public var blurPoints: CGFloat
    /// Multiplies the diffused heat, so a thin line still reaches the palette's yellow core.
    public var gain: CGFloat
    /// The grain's strength, as a share of full heat.
    public var grain: CGFloat
    /// Heat fades to nothing between these two shares of the height, measured from the top.
    public var fade: ClosedRange<CGFloat>?
    /// The color of no heat. The window ground for art that is the background, black for art laid
    /// over another surface with additive blending.
    public var ground: HeatPalette.Ground

    public init(
        blurPoints: CGFloat, gain: CGFloat, grain: CGFloat, fade: ClosedRange<CGFloat>? = nil,
        ground: HeatPalette.Ground = .window
    ) {
        self.blurPoints = blurPoints
        self.gain = gain
        self.grain = grain
        self.fade = fade
        self.ground = ground
    }
}

/// Renders heat strokes into a picture with Core Image.
@MainActor
public enum HeatCanvas {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    // Filters run in sRGB, as the Paper designs' SVG filters do, so the diffusion matches them.
    private static let context = CIContext(options: [
        .workingColorSpace: colorSpace, .outputColorSpace: colorSpace, .cacheIntermediates: false,
    ])

    /// Draws `strokes`, given in points with the origin at the top left, into a `size` picture at
    /// `scale` pixels per point.
    public static func render(
        _ strokes: [HeatStroke], size: CGSize, scale: CGFloat, development: HeatDevelopment
    ) -> CGImage? {
        guard let heat = heatField(strokes, size: size, scale: scale, fade: development.fade) else {
            return nil
        }
        let extent = heat.extent
        let diffused = heat.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(development.blurPoints * scale))
            .cropped(to: extent)
        let gained = diffused.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: development.gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: development.gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: development.gain, w: 0),
            ])
        let grained = grain(development.grain, extent: extent)
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: gained])
        guard let gradient = HeatPalette.gradient(ground: development.ground) else { return nil }
        let mapped = grained.applyingFilter(
            "CIColorMap", parameters: ["inputGradientImage": CIImage(cgImage: gradient)])
        return context.createCGImage(mapped, from: extent, format: .RGBA8, colorSpace: colorSpace)
    }

    /// The strokes in white on black: how hot each pixel is before it diffuses.
    private static func heatField(
        _ strokes: [HeatStroke], size: CGSize, scale: CGFloat, fade: ClosedRange<CGFloat>?
    ) -> CIImage? {
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
            let canvas = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        canvas.setFillColor(gray: 0, alpha: 1)
        canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))
        canvas.translateBy(x: 0, y: CGFloat(height))
        canvas.scaleBy(x: scale, y: -scale)
        for stroke in strokes where stroke.heat > 0 && stroke.width > 0 {
            canvas.setStrokeColor(gray: min(stroke.heat, 1), alpha: 1)
            canvas.setLineWidth(stroke.width)
            canvas.setLineCap(stroke.cap)
            canvas.addPath(stroke.path)
            canvas.strokePath()
        }
        if let fade { fadeOut(canvas, size: size, between: fade) }
        return canvas.makeImage().map { CIImage(cgImage: $0) }
    }

    /// Cools everything below the fade to black, so text can sit on clean ground.
    private static func fadeOut(_ canvas: CGContext, size: CGSize, between fade: ClosedRange<CGFloat>) {
        let top = size.height * fade.lowerBound
        let bottom = size.height * fade.upperBound
        let gray = CGColorSpaceCreateDeviceGray()
        let colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 1)] as CFArray
        if let ramp = CGGradient(colorsSpace: gray, colors: colors, locations: [0, 1]) {
            canvas.drawLinearGradient(
                ramp, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
        }
        canvas.setFillColor(gray: 0, alpha: 1)
        canvas.fill(CGRect(x: 0, y: bottom, width: size.width, height: max(size.height - bottom, 0)))
    }

    /// Zero-mean camera grain: per-pixel noise centered on no change.
    private static func grain(_ strength: CGFloat, extent: CGRect) -> CIImage {
        let share = strength / 3
        let noise = CIImage(color: .clear).cropped(to: extent)
        guard strength > 0, let random = CIFilter(name: "CIRandomGenerator")?.outputImage else {
            return noise
        }
        return random.cropped(to: extent).applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: share, y: share, z: share, w: 0),
                "inputGVector": CIVector(x: share, y: share, z: share, w: 0),
                "inputBVector": CIVector(x: share, y: share, z: share, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -strength / 2, y: -strength / 2, z: -strength / 2, w: 0),
            ])
    }
}
