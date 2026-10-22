import CoreGraphics
import ErstModel

/// Cleans recognized lines before they are read: drops text no one can see, and joins the
/// fragments of one line that the accessibility tree splits, such as one element per digit.
enum TextRows {
    /// Lines shorter than this share of the screen's height cannot be read. Collapsed menus and
    /// hidden panels report boxes this thin.
    static let minimumHeight: CGFloat = 0.003
    /// Fragments of one line sit closer than this many line heights apart, about a space's width.
    private static let fragmentGapLineHeights: CGFloat = 0.6
    /// Fragments closer than this many line heights touch, as the letters of one word do.
    private static let touchingGapLineHeights: CGFloat = 0.05
    /// Fragments overlap at most this many line heights, so two reads of one place stay apart.
    private static let overlapLineHeights: CGFloat = 0.5
    /// Fragments of one line share a baseline within this many line heights.
    private static let sameRowLineHeights: CGFloat = 0.3
    /// Fragments of one line share a font size.
    private static let sameSizeRatio: ClosedRange<CGFloat> = 0.8...1.25

    /// The lines someone can read, with each line's fragments joined left to right.
    static func readable(_ lines: [TextLine]) -> [TextLine] {
        var joined: [TextLine] = []
        let visible = lines.filter { $0.box.height >= minimumHeight }
        for line in visible.sorted(by: { $0.box.minX < $1.box.minX }) {
            if let index = joined.lastIndex(where: { continues(line, after: $0) }) {
                joined[index] = join(joined[index], line)
            } else {
                joined.append(line)
            }
        }
        return joined
    }

    private static func continues(_ line: TextLine, after fragment: TextLine) -> Bool {
        let height = min(line.box.height, fragment.box.height)
        guard height > 0,
            abs(line.box.midY - fragment.box.midY) < height * sameRowLineHeights,
            sameSizeRatio.contains(line.box.height / fragment.box.height)
        else { return false }
        let gap = line.box.minX - fragment.box.maxX
        return gap > -height * overlapLineHeights && gap < height * fragmentGapLineHeights
    }

    /// Touching fragments join without a space when one is a single character or the seam is not
    /// between two letters, as in "96.3" read one element per digit. Touching words keep a space,
    /// because the tree trims the space that separated them.
    private static func join(_ fragment: TextLine, _ line: TextLine) -> TextLine {
        let height = min(line.box.height, fragment.box.height)
        let touches = line.box.minX - fragment.box.maxX < height * touchingGapLineHeights
        let seamIsLetters =
            (fragment.text.last?.isLetter ?? false) && (line.text.first?.isLetter ?? false)
        let isSingle = fragment.text.count == 1 || line.text.count == 1
        let glued = touches && (isSingle || !seamIsLetters)
        return TextLine(
            text: fragment.text + (glued ? "" : " ") + line.text,
            box: fragment.box.union(line.box))
    }
}
