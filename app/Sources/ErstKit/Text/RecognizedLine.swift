import CoreGraphics
import Foundation

/// Where a line's text came from.
public enum TextSource: Sendable, Equatable {
    /// Read from the pixels by text recognition.
    case ocr
    /// Read from the focused window's accessibility tree, so the text is exact.
    case accessibility
}

/// One recognized line of text with a normalized bounding box.
public struct RecognizedLine: Sendable, Equatable {
    /// The recognized text, trimmed but otherwise unchanged.
    public let text: String
    /// Normalized box in the range 0 to 1, origin at the top left.
    public let box: CGRect
    /// Where the text came from.
    public let source: TextSource
    /// False when the box is an estimate, such as one row of a text area or a line whose text was
    /// cut; such a line never hides OCR by position alone.
    public let boxIsExact: Bool

    /// Creates a recognized line.
    public init(
        text: String, box: CGRect, source: TextSource = .ocr, boxIsExact: Bool = true
    ) {
        self.text = text
        self.box = box
        self.source = source
        self.boxIsExact = boxIsExact
    }
}
