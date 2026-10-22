import SwiftUI

/// Text with the search terms marked: butter, a step heavier, on a faint butter wash.
enum TermHighlight {
    /// `markedFont` is the surrounding style's medium weight, so a mark never changes the size.
    static func attributed(
        _ text: String, terms: [String], base: Color, markedFont: Font
    ) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        var endsWithMark = false
        while cursor < text.endIndex {
            guard let match = nextMatch(in: text, from: cursor, terms: terms) else {
                result.append(plain(String(text[cursor...]), base))
                break
            }
            let gap = text[cursor..<match.lowerBound]
            // Terms a space apart read as one phrase, so the mark runs on across the space.
            let joinsMark = endsWithMark && !gap.isEmpty && gap.allSatisfy(\.isWhitespace)
            if !joinsMark, !gap.isEmpty {
                result.append(plain(String(gap), base))
            }
            var marked = AttributedString(
                String(text[(joinsMark ? cursor : match.lowerBound)..<match.upperBound]))
            marked.foregroundColor = .erstButter
            marked.backgroundColor = .erstMatchWash
            marked.font = markedFont
            result.append(marked)
            endsWithMark = true
            cursor = match.upperBound
        }
        return result
    }

    /// Whether any term appears in the text, ignoring case and accents.
    static func matches(_ text: String, terms: [String]) -> Bool {
        nextMatch(in: text, from: text.startIndex, terms: terms) != nil
    }

    private static func plain(_ text: String, _ color: Color) -> AttributedString {
        var part = AttributedString(text)
        part.foregroundColor = color
        return part
    }

    /// The earliest match from `start`, and the longest one when two start together.
    private static func nextMatch(
        in text: String, from start: String.Index, terms: [String]
    ) -> Range<String.Index>? {
        var best: Range<String.Index>?
        for term in terms where !term.isEmpty {
            guard
                let range = text.range(
                    of: term, options: [.caseInsensitive, .diacriticInsensitive],
                    range: start..<text.endIndex)
            else { continue }
            if let current = best,
                range.lowerBound > current.lowerBound
                    || (range.lowerBound == current.lowerBound && range.upperBound <= current.upperBound)
            {
                continue
            }
            best = range
        }
        return best
    }
}
