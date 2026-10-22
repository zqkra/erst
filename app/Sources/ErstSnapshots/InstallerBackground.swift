import AppKit
import CoreText
import ErstUI
import ImageIO
import UniformTypeIdentifiers

/// Renders the installer window's background for `scripts/build-dmg.sh` with the same heat
/// renderer the welcome uses: the echoes at 1x and 2x, and the caption on the clean ground below.
@MainActor
enum InstallerBackground {
    private enum Failure: Error {
        case render
        case write(String)
    }

    private static let captionFontName = "SchibstedGrotesk-Regular"
    private static let captionSizePoints: CGFloat = 13
    /// The theme's secondary text, `#9B988F`.
    private static let captionGray = NSColor(
        srgbRed: 0x9B / 255, green: 0x98 / 255, blue: 0x8F / 255, alpha: 1)

    static func write(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scale in [1, 2] {
            guard
                let art = HeatCanvas.render(
                    InstallerArt.strokes(), size: InstallerArt.size, scale: CGFloat(scale),
                    development: InstallerArt.development),
                let image = captioned(art, scale: CGFloat(scale))
            else { throw Failure.render }
            let name = scale == 1 ? "installer-background.png" : "installer-background@2x.png"
            try writePNG(image, to: folder.appending(path: name))
        }
    }

    private static func captioned(_ art: CGImage, scale: CGFloat) -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: art.width, height: art.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(art, in: CGRect(x: 0, y: 0, width: art.width, height: art.height))
        let font = CTFontCreateWithName(captionFontName as CFString, captionSizePoints * scale, nil)
        let caption = NSAttributedString(
            string: InstallerArt.caption,
            attributes: [.font: font, .foregroundColor: captionGray])
        let line = CTLineCreateWithAttributedString(caption)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        // Core Graphics counts up from the bottom; the art counts down from the top.
        context.textPosition = CGPoint(
            x: (CGFloat(art.width) - CGFloat(width)) / 2,
            y: CGFloat(art.height) - InstallerArt.captionBaselineY * scale)
        CTLineDraw(line, context)
        return context.makeImage()
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.write(url.path) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.write(url.path) }
    }
}
