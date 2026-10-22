import CoreGraphics
import ErstModel

/// One block of recognized text, in the form that reads best.
public enum ReadingBlock: Equatable, Sendable {
    /// Lines of sentences and rows, with wrapped lines joined so they reflow.
    case text([ReadingLine])
    /// Short items stacked one per line on screen, such as a sidebar, a menu, or tabs.
    case items([String])
    /// A list whose rows pair a title with a value on its right, such as channels with viewer
    /// counts, senders with times, or settings with their values.
    case entries([ReadingEntry])
}

/// One line of a text block.
public struct ReadingLine: Equatable, Sendable {
    public let text: String
    /// Supporting text: pieces side by side on screen, such as a name, a handle, and a time, or
    /// smaller print than the block's main text, such as a count under a title.
    public let isDetail: Bool

    public init(_ text: String, isDetail: Bool = false) {
        self.text = text
        self.isDetail = isDetail
    }
}

/// One row of a list: its title, the value on its right, and the lines just under the title.
public struct ReadingEntry: Equatable, Sendable {
    public let title: String
    public let value: String
    public let details: [String]

    public init(_ title: String, value: String, details: [String] = []) {
        self.title = title
        self.value = value
        self.details = details
    }
}

/// Groups recognized lines into columns, then returns them in the order a person reads them.
enum TextReadingOrder {
    /// A line farther below the previous one than this many line heights starts a new block.
    private static let blockGapLineHeights: CGFloat = 1.6
    /// A line this close under the previous one, and starting where it starts, may wrap it.
    private static let wrapGapLineHeights: CGFloat = 0.6
    /// A line wraps into the next only when it fills this share of its column's widest line.
    private static let wrapFill: CGFloat = 0.6
    /// Wrapped lines of one paragraph share a font size; a title over its smaller subtitle does not.
    static let sameSize: ClosedRange<CGFloat> = 0.8...1.25
    /// Lines whose centers sit closer than this many heights apart share a row.
    static let sameRowLineHeights: CGFloat = 0.5
    /// Items that share a row, such as a name, a handle, and a time, keep a visible gap.
    private static let rowSeparator = "  "
    /// A detail line sits this close under its entry's title, closer than the next entry.
    private static let detailGapLineHeights: CGFloat = 0.5
    /// An entry shows at most this many detail lines; more means the run is not a list.
    private static let maximumDetails = 2
    private static let minimumEntryCount = 2

    /// Columns run left to right, and each column runs top to bottom, then left to right. A value
    /// that belongs to a row follows the row.
    static func order(_ lines: [TextLine]) -> [TextLine] {
        orderedColumns(lines).flatMap { $0.flatMap { [$0.line] + $0.values } }
    }

    /// The text as a person reads it: one block per run of nearby lines in a column. Wrapped lines
    /// join with a space so they reflow, and lines on one row keep a gap. A run of short lines
    /// stacked one under another becomes a list of items, and rows with values become entries.
    static func blocks(_ lines: [TextLine]) -> [ReadingBlock] {
        var blocks: [ReadingBlock] = []
        for column in orderedColumns(lines) {
            let widest = column.map(\.line.box.width).max() ?? 0
            var run: [Linked] = []
            for piece in column {
                let link = run.last.map { relation(of: piece.line, below: $0.piece.line, widest: widest) }
                if link == .newBlock {
                    blocks += readingBlocks(of: run)
                    run = []
                }
                run.append(Linked(piece: piece, relation: run.isEmpty ? nil : link))
            }
            blocks += readingBlocks(of: run)
        }
        return blocks
    }

    // MARK: Runs

    /// A run with rows that carry values reads as entries, with the lines around them as text.
    private static func readingBlocks(of run: [Linked]) -> [ReadingBlock] {
        guard !run.isEmpty else { return [] }
        guard let first = run.firstIndex(where: { !$0.piece.values.isEmpty }) else {
            return [block(from: run)]
        }
        var entries: [ReadingEntry] = []
        var index = first
        while index < run.count, !run[index].piece.values.isEmpty {
            let title = run[index].piece
            var details: [String] = []
            index += 1
            while index < run.count, details.count < maximumDetails,
                run[index].piece.values.isEmpty,
                isDetail(run[index].piece.line, under: run[index - 1].piece.line)
            {
                details.append(run[index].piece.line.text)
                index += 1
            }
            entries.append(
                ReadingEntry(
                    title.line.text, value: title.values.map(\.text).joined(separator: rowSeparator),
                    details: details))
        }
        guard entries.count >= minimumEntryCount else { return [block(from: run)] }
        let before = Array(run[..<first])
        let after = Array(run[index...])
        return (before.isEmpty ? [] : [block(from: before)]) + [.entries(entries)]
            + readingBlocks(of: after)
    }

    private static func isDetail(_ line: TextLine, under above: TextLine) -> Bool {
        let height = max(above.box.height, .ulpOfOne)
        return line.box.minY - above.box.maxY < height * detailGapLineHeights
            && abs(line.box.minX - above.box.minX) < height
    }

    /// The most words and characters a line can hold and still read as one item of a list.
    private static let maximumItemWords = 3
    private static let maximumItemCharacters = 28
    private static let minimumItemCount = 3

    private static func block(from run: [Linked]) -> ReadingBlock {
        let firstHeight = max(run.first?.piece.line.box.height ?? 0, .ulpOfOne)
        let isList =
            run.count >= minimumItemCount
            && run.dropFirst().allSatisfy { $0.relation == .nextLine }
            && run.allSatisfy { $0.piece.values.isEmpty && isItem($0.piece.line.text) }
            && run.allSatisfy { sameSize.contains($0.piece.line.box.height / firstHeight) }
        if isList { return .items(run.map(\.piece.line.text)) }
        var lines: [(text: String, height: CGFloat, isRow: Bool)] = []
        for linked in run {
            let piece = linked.piece
            let text = ([piece.line.text] + piece.values.map(\.text)).joined(separator: rowSeparator)
            let hasValues = !piece.values.isEmpty
            guard let last = lines.last, linked.relation != .nextLine, linked.relation != .newBlock
            else {
                lines.append((text, piece.line.box.height, hasValues))
                continue
            }
            lines[lines.count - 1] =
                linked.relation == .sameRow
                ? (last.text + rowSeparator + text, last.height, true)
                : (last.text + (last.text.hasSuffix("-") ? "" : " ") + text, last.height, last.isRow)
        }
        let tallest = lines.map(\.height).max() ?? 0
        return .text(
            lines.map {
                ReadingLine($0.text, isDetail: $0.isRow || $0.height < tallest * sameSize.lowerBound)
            })
    }

    private static func isItem(_ text: String) -> Bool {
        text.count <= maximumItemCharacters
            && text.split(whereSeparator: \.isWhitespace).count <= maximumItemWords
    }

    private struct Linked {
        let piece: TextPiece
        let relation: Relation?
    }

    private enum Relation {
        case sameRow
        case wrapped
        case nextLine
        case newBlock
    }

    private static func relation(of line: TextLine, below above: TextLine, widest: CGFloat) -> Relation {
        let height = max(above.box.height, .ulpOfOne)
        if abs(line.box.midY - above.box.midY) < height * sameRowLineHeights { return .sameRow }
        let gap = line.box.minY - above.box.maxY
        if gap > height * blockGapLineHeights { return .newBlock }
        let aligned = abs(line.box.minX - above.box.minX) < height
        let sameSize = sameSize.contains(line.box.height / height)
        let fills = above.box.width >= widest * wrapFill
        return gap < height * wrapGapLineHeights && aligned && sameSize && fills ? .wrapped : .nextLine
    }

    private static func orderedColumns(_ lines: [TextLine]) -> [[TextPiece]] {
        TextColumns.columns(of: TextRows.readable(lines))
    }
}

extension Array where Element == TextLine {
    /// Readable lines in column reading order, so sidebars and content columns do not interleave.
    var inReadingOrder: [TextLine] {
        TextReadingOrder.order(self)
    }

    /// The lines as blocks of readable text, in reading order.
    public var readingBlocks: [ReadingBlock] {
        TextReadingOrder.blocks(self)
    }
}
