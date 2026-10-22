import CoreGraphics
import CoreText
import CoreVideo
import ErstKit
import Foundation

/// Proves that reading only the parts of a frame that changed keeps every word a whole read finds,
/// including a word changed inside a line, words typed at the end of a line, and a new line.
enum ProbeIncrementalVerification {
    private enum Failure: Error {
        case check(String)
    }

    private struct Placed {
        let text: String
        /// Top-left position in pixels of the 2560 by 1440 frame.
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
    }

    private static let frameWidth = 2560
    private static let frameHeight = 1440

    private static let before = [
        Placed(text: "Quarterly planning notes for the design review", x: 120, y: 160, size: 22),
        Placed(text: "Status: idle while the build finishes", x: 120, y: 220, size: 22),
        Placed(text: "Total 12", x: 120, y: 280, size: 22),
        Placed(text: "Owners and deadlines are listed below", x: 120, y: 340, size: 22),
        Placed(text: "Inbox", x: 1800, y: 160, size: 18),
        Placed(text: "Archive", x: 1800, y: 210, size: 18),
        Placed(text: "Drafts", x: 1800, y: 260, size: 18),
        Placed(text: "Settings", x: 1800, y: 310, size: 18),
        Placed(text: "Remember everything you saw on this screen", x: 120, y: 1200, size: 20),
    ]

    private static let after =
        before.map { placed in
            switch placed.text {
            case "Status: idle while the build finishes":
                Placed(
                    text: "Status: busy while the build finishes", x: placed.x, y: placed.y, size: placed.size
                )
            case "Total 12":
                Placed(text: "Total 12 items", x: placed.x, y: placed.y, size: placed.size)
            default:
                placed
            }
        } + [Placed(text: "A new message arrived from Maya", x: 1200, y: 700, size: 20)]

    /// A video playing beside a page: most of the frame changes, none of the change is text, and
    /// the page's text around it stays put.
    private static let page = [
        Placed(text: "Recommended for you", x: 1900, y: 120, size: 22),
        Placed(text: "Live coding session tonight", x: 1900, y: 220, size: 18),
        Placed(text: "Weekly design review notes", x: 1900, y: 300, size: 18),
        Placed(text: "How we ship a release", x: 1900, y: 380, size: 18),
        Placed(text: "Mixing a song from scratch", x: 1900, y: 460, size: 18),
        Placed(text: "A quiet walk in the rain", x: 1900, y: 540, size: 18),
        Placed(text: "Comments are turned off", x: 120, y: 1300, size: 20),
    ]

    static func run() async throws {
        try await verifyEditedText()
        try await verifyVideoBesidePage()
    }

    private static func verifyVideoBesidePage() async throws {
        try await Task.detached(priority: .utility) {
            let videoArea = CGRect(x: 80, y: 80, width: 1700, height: 1150)
            let outcome = try await IncrementalReadCheck.compare(
                previous: CapturedFrame(
                    pixelBuffer: try makeFrame(page, video: (videoArea, 0.2)), capturedAt: Date(),
                    displayID: 1),
                current: CapturedFrame(
                    pixelBuffer: try makeFrame(page, video: (videoArea, 0.7)), capturedAt: Date(),
                    displayID: 1))
            guard outcome.regionCount != nil else {
                throw Failure.check("A changing video beside a page must not read the whole frame")
            }
            let found = try checkAgainstTruth(outcome, truth: page)
            print(
                String(
                    format:
                        "Video OCR verification passed: the video region read alone, %d of %d true words; "
                        + "%.0f ms instead of %.0f ms for a whole read",
                    found, words(page.map(\.text)).count, outcome.incrementalMilliseconds,
                    outcome.wholeMilliseconds))
        }.value
    }

    private static func verifyEditedText() async throws {
        try await Task.detached(priority: .utility) {
            let outcome = try await IncrementalReadCheck.compare(
                previous: CapturedFrame(pixelBuffer: try makeFrame(before), capturedAt: Date(), displayID: 1),
                current: CapturedFrame(pixelBuffer: try makeFrame(after), capturedAt: Date(), displayID: 1))
            guard let regions = outcome.regionCount else {
                throw Failure.check("A few changed lines must not read the whole frame")
            }
            let found = try checkAgainstTruth(outcome, truth: after)
            guard outcome.incremental.contains(where: { $0.text.contains("Total 12 items") }) else {
                throw Failure.check(
                    "Words typed at the end of a line must read as one line: \(outcome.incremental.map(\.text))"
                )
            }
            print(
                String(
                    format:
                        "Incremental OCR verification passed: %d regions read, %d of %d true words; "
                        + "%.0f ms instead of %.0f ms for a whole read",
                    regions, found, words(after.map(\.text)).count, outcome.incrementalMilliseconds,
                    outcome.wholeMilliseconds))
        }.value
    }

    /// Two whole reads of the same unchanged text can differ ("of" against "off"), because Vision
    /// reads each line in the context of the whole frame. So the incremental read is held to the
    /// truth: it must find at least as many of the frame's real words as the worse of the two whole
    /// reads it stands between, and add nothing a whole read would not. Returns the words it found.
    private static func checkAgainstTruth(
        _ outcome: IncrementalReadCheck.Outcome, truth: [Placed]
    ) throws -> Int {
        let real = words(truth.map(\.text))
        let previous = words(outcome.previous.map(\.text))
        let whole = words(outcome.whole.map(\.text))
        let incremental = words(outcome.incremental.map(\.text))
        let floor = min(previous.intersection(real).count, whole.intersection(real).count)
        let found = incremental.intersection(real).count
        guard found >= floor else {
            throw Failure.check(
                "Incremental read found \(found) real words, fewer than \(floor); missing "
                    + "\(real.subtracting(incremental).sorted())")
        }
        let extra = incremental.subtracting(real).subtracting(previous.union(whole))
        guard extra.isEmpty else {
            throw Failure.check("Incremental read added words no whole read found: \(extra.sorted())")
        }
        return found
    }

    private static func words(_ texts: [String]) -> Set<String> {
        Set(
            texts.flatMap { text in
                text.lowercased()
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map(String.init)
            })
    }

    /// Draws the texts on white. `video` paints a gradient over an area, standing in for a frame of
    /// moving picture: every pixel in it changes when the shade changes.
    private static func makeFrame(
        _ texts: [Placed], video: (area: CGRect, shade: CGFloat)? = nil
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw Failure.check("Cannot allocate the incremental OCR fixture")
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
            throw Failure.check("Cannot draw the incremental OCR fixture")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight))
        if let video {
            let area = CGRect(
                x: video.area.minX, y: CGFloat(frameHeight) - video.area.maxY,
                width: video.area.width, height: video.area.height)
            let colors = [
                CGColor(red: video.shade, green: 0.2, blue: 1 - video.shade, alpha: 1),
                CGColor(red: 0.1, green: video.shade, blue: 0.3, alpha: 1),
            ]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])
            {
                context.saveGState()
                context.clip(to: area)
                context.drawLinearGradient(
                    gradient, start: CGPoint(x: area.minX, y: area.minY),
                    end: CGPoint(x: area.maxX, y: area.maxY), options: [])
                context.restoreGState()
            }
        }
        for placed in texts {
            let font = CTFontCreateWithName("Helvetica" as CFString, placed.size, nil)
            let text = NSAttributedString(
                string: placed.text,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                        gray: 0, alpha: 1),
                ])
            context.textPosition = CGPoint(x: placed.x, y: CGFloat(frameHeight) - placed.y)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        return pixelBuffer
    }
}
