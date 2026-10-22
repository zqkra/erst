import CoreGraphics
import Foundation

/// Joins OCR lines with the exact and estimated lines read from the accessibility tree.
public enum TextMerge {
    /// Box tolerance in normalized units, so rounding at an element edge does not keep a duplicate.
    public static let tolerance: CGFloat = 0.002
    /// Shortest OCR matching key an estimated box may hide, so a stray "OK" or a page number stays.
    public static let minimumEstimatedKeyLength = 4

    /// Keeps every accessibility line, and the OCR lines that no accessibility line covers.
    ///
    /// An exact accessibility box hides an OCR line whose center falls inside it, because the tree
    /// already gave that text at that place. An estimated box, from one row of a text area or from a
    /// line whose text was cut, hides an OCR line only when the OCR line's matching key sits inside
    /// the estimated line's key, because the tree does not know the real geometry.
    public static func merge(
        ocr: [RecognizedLine], accessibility: [RecognizedLine]
    ) -> (lines: [RecognizedLine], replaced: Int) {
        let exactBoxes = accessibility.filter { $0.boxIsExact }.map(\.box)
            .filter { $0.width > 0 && $0.height > 0 }
        let estimatedKeys = accessibility.filter { !$0.boxIsExact }
            .map { matchingKey($0.text) }
            .filter { !$0.isEmpty }
        var lines = accessibility
        var replaced = 0
        for line in ocr {
            if hides(line, exactBoxes: exactBoxes, estimatedKeys: estimatedKeys) {
                replaced += 1
            } else {
                lines.append(line)
            }
        }
        return (lines, replaced)
    }

    /// Whether an accessibility line already carries this OCR line's text at its place.
    private static func hides(
        _ line: RecognizedLine, exactBoxes: [CGRect], estimatedKeys: [String]
    ) -> Bool {
        let center = CGPoint(x: line.box.midX, y: line.box.midY)
        let isInsideExactBox = exactBoxes.contains {
            $0.insetBy(dx: -tolerance, dy: -tolerance).contains(center)
        }
        guard !isInsideExactBox else { return true }
        let key = matchingKey(line.text)
        guard key.count >= minimumEstimatedKeyLength else { return false }
        return estimatedKeys.contains { $0.contains(key) }
    }

    /// Text lowered, folded, and stripped to letters and digits, so two reads compare by words.
    private static func matchingKey(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.filter { $0.isLetter || $0.isNumber }
    }
}
