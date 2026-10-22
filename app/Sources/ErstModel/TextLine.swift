import CoreGraphics
import Foundation

/// A recognized line of text with a bounding box normalized to its frame, origin top-left.
public struct TextLine: Hashable, Sendable {
    public let text: String
    public let box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}
