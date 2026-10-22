import CoreGraphics
import ErstModel

/// A line, with the values that sit on its row to its right, such as a count beside a name.
struct TextPiece {
    let line: TextLine
    /// Left to right.
    var values: [TextLine] = []
}

/// Splits lines into columns, joins a column of short values to the rows they belong to, and
/// orders the columns left to right and each column top to bottom.
enum TextColumns {
    /// A line joins a column when it covers at least this share of the narrower x range.
    private static let minimumColumnOverlap: CGFloat = 0.5
    /// A value is short, such as "96,3 mil", "3:42 PM", or "On".
    private static let maximumValueWords = 3
    private static let maximumValueCharacters = 16
    /// A value sits at most this many line heights right of its row's text.
    private static let maximumValueGapLineHeights: CGFloat = 8
    /// A column of values joins rows only when this share of its values finds a row.
    private static let minimumValueCoverage: CGFloat = 0.75
    private static let minimumValueCount = 2

    static func columns(of lines: [TextLine]) -> [[TextPiece]] {
        var columns = group(lines)
        attachValues(&columns)
        return
            columns
            .filter { !$0.pieces.isEmpty }
            .sorted { ($0.leftEdge, $0.rightEdge) < ($1.leftEdge, $1.rightEdge) }
            .map { $0.pieces.sorted { readsBefore($0.line, $1.line) } }
    }

    // MARK: Values

    /// A column of short lines, each on the row of a line in a column to its left, belongs to
    /// those rows: a sidebar's counts, a mailbox's times, a settings list's values.
    private static func attachValues(_ columns: inout [Column]) {
        for valueIndex in columns.indices {
            let candidates = columns[valueIndex].pieces
            guard candidates.count >= minimumValueCount,
                candidates.allSatisfy({ $0.values.isEmpty && isValue($0.line.text) })
            else { continue }
            var best: (column: Int, rows: [Int: Int])?
            for rowIndex in columns.indices
            where rowIndex != valueIndex && columns[rowIndex].leftEdge < columns[valueIndex].leftEdge {
                var rows: [Int: Int] = [:]
                for (offset, candidate) in candidates.enumerated() {
                    rows[offset] = row(for: candidate.line, in: columns[rowIndex].pieces)
                }
                if rows.count > (best?.rows.count ?? 0) { best = (rowIndex, rows) }
            }
            guard let best,
                CGFloat(best.rows.count) >= CGFloat(candidates.count) * minimumValueCoverage
            else { continue }
            for (offset, rowOffset) in best.rows {
                columns[best.column].pieces[rowOffset].values.append(candidates[offset].line)
                columns[best.column].pieces[rowOffset].values.sort { $0.box.minX < $1.box.minX }
            }
            columns[valueIndex].pieces = candidates.enumerated()
                .filter { best.rows[$0.offset] == nil }
                .map(\.element)
        }
    }

    /// The nearest line on the value's row that ends left of it, within reach.
    private static func row(for value: TextLine, in pieces: [TextPiece]) -> Int? {
        let height = max(value.box.height, .ulpOfOne)
        var best: (offset: Int, distance: CGFloat)?
        for (offset, piece) in pieces.enumerated() {
            let line = piece.line
            let rowDistance = abs(line.box.midY - value.box.midY)
            let gap = value.box.minX - line.box.maxX
            guard rowDistance < min(height, line.box.height) * TextReadingOrder.sameRowLineHeights,
                gap >= 0, gap <= height * maximumValueGapLineHeights
            else { continue }
            if rowDistance < (best?.distance ?? .infinity) { best = (offset, rowDistance) }
        }
        return best?.offset
    }

    private static func isValue(_ text: String) -> Bool {
        text.count <= maximumValueCharacters
            && text.split(whereSeparator: \.isWhitespace).count <= maximumValueWords
    }

    // MARK: Columns

    /// A wide line over two real columns, such as a toolbar above a sidebar and its counts, would
    /// merge them into one. Such bridges are set aside, the rest is grouped, and each bridge then
    /// joins the column under most of it without widening it.
    private static func group(_ lines: [TextLine]) -> [Column] {
        var standing = lines
        var bridges: [TextLine] = []
        for _ in 0..<maximumBridgePasses {
            let found = Set(groupOnce(standing).flatMap(bridges(in:)))
            guard !found.isEmpty else { break }
            bridges += standing.filter { found.contains($0) }
            standing.removeAll { found.contains($0) }
        }
        var columns = groupOnce(standing)
        for bridge in bridges {
            if let index = columnIndex(for: bridge, in: columns, minimumOverlap: .ulpOfOne) {
                columns[index].pieces.append(TextPiece(line: bridge))
            } else {
                columns.append(Column(line: bridge))
            }
        }
        return columns
    }

    private static let maximumBridgePasses = 8
    /// At most this share of a column's lines can be bridges; more means it really is one column.
    private static let maximumBridgeShare = 4

    /// The fewest widest lines whose removal splits the column into two columns of at least two
    /// lines each, or none.
    private static func bridges(in column: Column) -> [TextLine] {
        let lines = column.pieces.map(\.line).sorted { $0.box.width > $1.box.width }
        let limit = min(max(1, lines.count / maximumBridgeShare), lines.count - 4)
        guard limit >= 1 else { return [] }
        for count in 1...limit {
            let parts = groupOnce(Array(lines.dropFirst(count)))
            if parts.filter({ $0.pieces.count >= 2 }).count >= 2 { return Array(lines.prefix(count)) }
        }
        return []
    }

    private static func groupOnce(_ lines: [TextLine]) -> [Column] {
        var columns: [Column] = []
        for line in lines.sorted(by: startsFirst) {
            if let index = columnIndex(for: line, in: columns) {
                columns[index].add(line)
            } else {
                columns.append(Column(line: line))
            }
        }
        return columns
    }

    /// The column whose x range overlaps this line the most, when it reaches the minimum share.
    private static func columnIndex(
        for line: TextLine, in columns: [Column], minimumOverlap: CGFloat = minimumColumnOverlap
    ) -> Int? {
        var best: (index: Int, overlap: CGFloat)?
        for (index, column) in columns.enumerated() {
            let overlap = overlapRatio(line.box, column)
            guard overlap >= minimumOverlap else { continue }
            if overlap > (best?.overlap ?? 0) {
                best = (index, overlap)
            }
        }
        return best?.index
    }

    private static func overlapRatio(_ box: CGRect, _ column: Column) -> CGFloat {
        let shared = min(box.maxX, column.rightEdge) - max(box.minX, column.leftEdge)
        guard shared > 0 else { return 0 }
        let narrower = min(box.width, column.width)
        guard narrower > 0 else { return 0 }
        return shared / narrower
    }

    private static func startsFirst(_ lhs: TextLine, _ rhs: TextLine) -> Bool {
        (lhs.box.minX, lhs.box.minY, lhs.text) < (rhs.box.minX, rhs.box.minY, rhs.text)
    }

    private static func readsBefore(_ lhs: TextLine, _ rhs: TextLine) -> Bool {
        (lhs.box.minY, lhs.box.minX, lhs.box.maxX, lhs.text)
            < (rhs.box.minY, rhs.box.minX, rhs.box.maxX, rhs.text)
    }

    private struct Column {
        private(set) var leftEdge: CGFloat
        private(set) var rightEdge: CGFloat
        var pieces: [TextPiece]

        init(line: TextLine) {
            leftEdge = line.box.minX
            rightEdge = line.box.maxX
            pieces = [TextPiece(line: line)]
        }

        var width: CGFloat { rightEdge - leftEdge }

        mutating func add(_ line: TextLine) {
            leftEdge = min(leftEdge, line.box.minX)
            rightEdge = max(rightEdge, line.box.maxX)
            pieces.append(TextPiece(line: line))
        }
    }
}
