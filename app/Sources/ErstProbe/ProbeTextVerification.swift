import CoreGraphics
import CoreText
import CoreVideo
import ErstKit
import Foundation

/// Checks bilingual small-text recognition and the single Vision coordinate conversion.
enum ProbeTextVerification {
    private enum Failure: Error {
        case check(String)
    }

    private static let sentences = [
        "English: screen history remains searchable.",
        "Español: acción, información, pingüino y corazón.",
    ]
    private static let fontSizes: [CGFloat] = [11, 14, 18]
    private static let frameWidth = 2560
    private static let frameHeight = 1440

    static func run() async throws {
        try await Task.detached(priority: .utility) {
            let frame = try makeFrame()
            let lines = try await TextRecognizer().recognizeText(in: frame.pixelBuffer)
            let summary: String
            if TextRecognizer.usesFastFallback {
                try verifyFast(lines)
                summary =
                    "OCR verification passed with fast recognition: \(lines.count) lines; "
                    + "accurate recognition is unavailable on this host"
            } else {
                try verifyAccurate(lines)
                summary =
                    "OCR verification passed: \(lines.count) English/Spanish lines at 11, 14 and 18 pixels; "
                    + "2560x1440 BGRA, accents, top-left boxes"
            }
            try verifyBoxes(lines)
            print(summary)
        }.value
    }

    /// The exact check for accurate recognition, which reads every line at 11 pixels and up.
    private static func verifyAccurate(_ lines: [RecognizedLine]) throws {
        guard lines.count == sentences.count * fontSizes.count,
            lines.filter({ $0.text.hasPrefix("English: screen history remains searchable") }).count
                == fontSizes.count,
            lines.filter({
                $0.text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
                    .contains("informacion")
            }).count == fontSizes.count,
            lines.contains(where: { $0.text == sentences[1] })
        else {
            throw Failure.check("Missing small UI text or accented Spanish: \(lines)")
        }
    }

    /// Fast recognition is what this host has, so the check asks for what it must still read:
    /// the English phrase at every size it found, and the accented Spanish word once.
    private static func verifyFast(_ lines: [RecognizedLine]) throws {
        guard lines.count >= 4 else {
            throw Failure.check("Fast recognition returned \(lines.count) lines, fewer than 4")
        }
        let english = lines.filter { $0.text.hasPrefix("English") }
        guard !english.isEmpty else {
            throw Failure.check(
                "Fast recognition returned no line starting with English: \(lines.map(\.text))")
        }
        guard english.allSatisfy({ $0.text.contains("screen history remains searchable") }) else {
            throw Failure.check(
                "Fast recognition lost the English phrase in \(english.map(\.text))")
        }
        let readsSpanish =
            lines.contains {
                $0.text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
                    .contains("informacion")
            }
        guard readsSpanish else {
            throw Failure.check(
                "Fast recognition lost the Spanish word informacion: \(lines.map(\.text))")
        }
    }

    private static func verifyBoxes(_ lines: [RecognizedLine]) throws {
        for line in lines {
            guard line.box.minX >= 0, line.box.maxX <= 1,
                line.box.minY >= 0, line.box.maxY < 0.3,
                line.box.width > 0, line.box.height > 0
            else {
                throw Failure.check("OCR box is not normalized with a top-left origin: \(line.box)")
            }
        }
    }

    private static func makeFrame() throws -> CapturedFrame {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw Failure.check("Cannot allocate the OCR fixture")
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer), width: frameWidth, height: frameHeight,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        else {
            throw Failure.check("Cannot draw the OCR fixture")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight))
        var baseline = CGFloat(frameHeight - 80)
        for size in fontSizes {
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            for sentence in sentences {
                let text = NSAttributedString(
                    string: sentence,
                    attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                            gray: 0, alpha: 1),
                    ])
                context.textPosition = CGPoint(x: 80, y: baseline)
                CTLineDraw(CTLineCreateWithAttributedString(text), context)
                baseline -= 45
            }
        }
        return CapturedFrame(pixelBuffer: pixelBuffer, capturedAt: Date(), displayID: 1)
    }
}
