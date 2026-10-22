import CoreGraphics
import ErstKit
import Foundation

/// Checks how exact and estimated accessibility lines replace OCR lines, without the screen.
enum ProbeMergeVerification {
    private enum Failure: Error {
        case check(String)
    }

    private static let accessibility = RecognizedLine(
        text: "Exact accessibility line",
        box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.05),
        source: .accessibility
    )
    /// One row of a text area: it covers the row, but its height is not the row's real geometry.
    private static let estimated = RecognizedLine(
        text: "Estimated text area row",
        box: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.05),
        source: .accessibility,
        boxIsExact: false
    )

    static func run() throws {
        try verifyExactBox()
        try verifyEstimatedBoxWithMatchingText()
        try verifyEstimatedBoxWithOtherText()
        print(
            "ErstProbe merge verification passed: exact boxes replace by place, estimated boxes only by text"
        )
    }

    private static func verifyExactBox() throws {
        let inside = RecognizedLine(
            text: "Noisy OCR line",
            box: CGRect(x: 0.2, y: 0.11, width: 0.2, height: 0.03)
        )
        let outside = RecognizedLine(
            text: "OCR line from another window",
            box: CGRect(x: 0.7, y: 0.6, width: 0.2, height: 0.03)
        )
        let merged = TextMerge.merge(ocr: [inside, outside], accessibility: [accessibility])
        guard merged.lines.count == 2 else {
            throw Failure.check("Exact box merge kept \(merged.lines.count) lines, expected 2")
        }
        guard merged.replaced == 1 else {
            throw Failure.check("Exact box merge replaced \(merged.replaced) OCR lines, expected 1")
        }
        guard merged.lines.first == accessibility, merged.lines.last == outside else {
            throw Failure.check("Exact box merge kept the wrong lines: \(merged.lines)")
        }
    }

    /// The OCR text differs in case and spacing, and the key still matches.
    private static func verifyEstimatedBoxWithMatchingText() throws {
        let matching = RecognizedLine(
            text: "Estimated TEXT   area row",
            box: CGRect(x: 0.2, y: 0.31, width: 0.2, height: 0.03)
        )
        let merged = TextMerge.merge(ocr: [matching], accessibility: [estimated])
        guard merged.lines == [estimated] else {
            throw Failure.check("Estimated box did not replace matching OCR text: \(merged.lines)")
        }
        guard merged.replaced == 1 else {
            throw Failure.check("Estimated box replaced \(merged.replaced) OCR lines, expected 1")
        }
    }

    /// Text drawn over the area, such as a find bar, sits inside the estimated box and stays.
    private static func verifyEstimatedBoxWithOtherText() throws {
        let other = RecognizedLine(
            text: "Find bar over the text area",
            box: CGRect(x: 0.2, y: 0.31, width: 0.2, height: 0.03)
        )
        let merged = TextMerge.merge(ocr: [other], accessibility: [estimated])
        guard merged.lines == [estimated, other] else {
            throw Failure.check("Estimated box dropped OCR text it does not hold: \(merged.lines)")
        }
        guard merged.replaced == 0 else {
            throw Failure.check("Estimated box replaced \(merged.replaced) OCR lines, expected 0")
        }
    }
}
