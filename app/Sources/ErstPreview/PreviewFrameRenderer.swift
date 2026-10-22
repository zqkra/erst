import CoreGraphics
import CoreText
import ErstModel
import Foundation

/// Draws a synthetic capture frame from the text lines of a preview moment.
enum PreviewFrameRenderer {
    static let frameWidth: CGFloat = 1600
    static let frameHeight: CGFloat = 1000

    private static let contentMargin: CGFloat = 40
    private static let contentTopInset: CGFloat = 84
    private static let bodyFontName = "SchibstedGrotesk-Regular"
    private static let boldFontName = "SchibstedGrotesk-Regular_SemiBold"

    /// App layouts and line boxes in PreviewContent are positioned for this content area.
    private static let contentRect = CGRect(
        x: contentMargin,
        y: contentTopInset,
        width: frameWidth - contentMargin * 2,
        height: frameHeight - contentTopInset - contentMargin
    )

    static func render(moment: Moment, lines: [TextLine], width: Int) -> CGImage? {
        let outputWidth = min(Int(frameWidth), max(320, width))
        let scale = CGFloat(outputWidth) / frameWidth
        let outputHeight = Int((frameHeight * scale).rounded())
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.scaleBy(x: scale, y: scale)

        let layout = layout(for: moment)
        fill(
            CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight),
            layout.background,
            context
        )
        context.saveGState()
        context.clip(to: convert(contentRect))
        drawContent(layout: layout, content: contentRect, context: context)
        drawLines(lines, layout: layout, context: context)
        context.restoreGState()
        return context.makeImage()
    }

    static func layout(for moment: Moment) -> PreviewLayout {
        switch moment.app.bundleID {
        case PreviewApps.x.bundleID: .xFeed
        case PreviewApps.whatsApp.bundleID: .whatsApp
        case PreviewApps.mail.bundleID: .mail
        case PreviewApps.notes.bundleID: .notes
        case PreviewApps.zed.bundleID: .editor
        case PreviewApps.safari.bundleID:
            moment.url?.host()?.contains("youtube") == true ? .youtube : .article
        default: .article
        }
    }

    private static func drawLines(_ lines: [TextLine], layout: PreviewLayout, context: CGContext) {
        let dark = layout.isDark
        let primary = dark ? PreviewPalette.darkInk : PreviewPalette.lightInk
        let secondary = dark ? PreviewPalette.darkSecondary : PreviewPalette.lightSecondary
        for line in lines {
            let rect = box(line.box)
            guard rect.width > 2, rect.height > 2 else { continue }
            let heading = rect.height >= 22
            let quiet = rect.height <= 14
            draw(
                line.text,
                in: rect,
                size: rect.height * 0.8,
                fontName: heading ? boldFontName : bodyFontName,
                color: quiet ? secondary : primary,
                context: context
            )
        }
    }

    private static func box(_ normalized: CGRect) -> CGRect {
        CGRect(
            x: normalized.minX * frameWidth,
            y: normalized.minY * frameHeight,
            width: normalized.width * frameWidth,
            height: normalized.height * frameHeight
        )
    }

    private static func draw(
        _ text: String,
        in rect: CGRect,
        size: CGFloat,
        fontName: String,
        color: CGColor,
        context: CGContext
    ) {
        guard !text.isEmpty, rect.width > 2, rect.height > 2 else { return }
        var fontSize = max(6, size)
        var line = makeLine(text, fontSize: fontSize, fontName: fontName, color: color)
        var width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if width > rect.width, width > 0 {
            fontSize = max(5, fontSize * rect.width / width)
            line = makeLine(text, fontSize: fontSize, fontName: fontName, color: color)
            width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let bottom = frameHeight - rect.maxY
        let baseline = bottom + (rect.height - (ascent + descent)) / 2 + descent
        context.textPosition = CGPoint(x: rect.minX, y: baseline)
        CTLineDraw(line, context)
    }

    private static func makeLine(
        _ text: String,
        fontSize: CGFloat,
        fontName: String,
        color: CGColor
    ) -> CTLine {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        return CTLineCreateWithAttributedString(attributed)
    }

    static func convert(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: frameHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func fill(_ rect: CGRect, _ color: CGColor, _ context: CGContext) {
        context.setFillColor(color)
        context.fill(convert(rect))
    }

    static func rounded(_ rect: CGRect, _ radius: CGFloat, _ color: CGColor, _ context: CGContext) {
        context.setFillColor(color)
        context.addPath(
            CGPath(roundedRect: convert(rect), cornerWidth: radius, cornerHeight: radius, transform: nil)
        )
        context.fillPath()
    }
}

extension PreviewLayout {
    var isDark: Bool {
        switch self {
        case .xFeed, .editor: true
        case .whatsApp, .youtube, .article, .mail, .notes: false
        }
    }
}
