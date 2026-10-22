import CoreGraphics
import CoreText
import CoreVideo
import Foundation

/// Draws the small frame that loads Vision's text models on a fresh process.
enum TextWarmUpImage {
    private static let width = 640
    private static let height = 200
    private static let fontSize: CGFloat = 24
    private static let baselineY: CGFloat = 88
    private static let leftInset: CGFloat = 24
    private static let text = "Erst reads the text on your screen"

    /// Creates a white BGRA frame with one large line of text for a warm-up request.
    static func make() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                    gray: 0, alpha: 1),
            ])
        context.textPosition = CGPoint(x: leftInset, y: baselineY)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        return buffer
    }
}
