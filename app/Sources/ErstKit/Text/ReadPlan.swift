import CoreGraphics

/// The parts of a kept frame to read again, and how their text joins the text of the last frame
/// that was read.
///
/// Pixels outside the changed tiles are the same bytes the last read saw, so their text is the
/// same text. Only the changed parts go through Vision, which is most of the CPU Erst spends.
struct ReadPlan: Sendable, Equatable {
    /// One part to read again. New text whose center lies in `core` replaces the old text that
    /// touches `core`. `read` adds a margin, so Vision sees the edges of what it reads.
    struct Region: Sendable, Equatable {
        let core: CGRect
        let read: CGRect
    }

    let regions: [Region]

    /// Above this share of the frame, one whole read costs about the same. Vision's cost follows
    /// the lines it reads, not the area, so a video that changes most of the screen still reads
    /// cheaper as a region than with the page's unchanged text around it.
    static let wholeFrameShare: CGFloat = 0.9
    /// One Vision call per frame: each call has a fixed cost of about 20 ms, and on real use three
    /// or four separate regions (204 to 238 ms) cost more than one whole read (137 ms). The parts
    /// join into the one rectangle around them.
    static let maximumRegions = 1
    /// Changed tiles this many tiles apart read as one part.
    private static let joinDistanceTiles = 2
    /// An old line this many of its heights beside a changed part joins it, so text typed at the
    /// end of a line rereads the whole line and a phrase never splits across two reads.
    private static let lineReachWidths: CGFloat = 1.5
    private static let lineReachHeights: CGFloat = 0.3
    private static let maximumGrowthPasses = 8

    /// Plans the read of a frame whose tiles changed as `changed` since the frame that held
    /// `previousLines`. Nil reads the whole frame. No regions means nothing changed.
    static func make(
        changed: [Bool], signature: TileSignature, previousLines: [RecognizedLine]
    ) -> ReadPlan? {
        let parts = changedParts(changed, signature: signature)
        guard !parts.isEmpty else { return ReadPlan(regions: []) }
        let aspect = CGFloat(signature.height) / CGFloat(max(signature.width, 1))
        var grown = parts
        for _ in 0..<maximumGrowthPasses {
            var grew = false
            for index in grown.indices {
                for line in previousLines where !grown[index].contains(line.box) {
                    let height = line.box.height
                    let reach = line.box.insetBy(
                        dx: -height * lineReachWidths * aspect, dy: -height * lineReachHeights)
                    guard reach.intersects(grown[index]) else { continue }
                    grown[index] = grown[index].union(line.box)
                    grew = true
                }
            }
            grown = merged(grown)
            guard grew else { break }
        }
        while grown.count > maximumRegions {
            grown = merged(joiningNearestPair(of: grown))
        }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let marginX = CGFloat(TileSignature.tileSide) / CGFloat(max(signature.width, 1))
        let marginY = CGFloat(TileSignature.tileSide) / CGFloat(max(signature.height, 1))
        let regions = grown.map { core in
            Region(core: core, read: core.insetBy(dx: -marginX, dy: -marginY).intersection(unit))
        }
        let share = regions.reduce(0) { $0 + $1.read.width * $1.read.height }
        return share > wholeFrameShare ? nil : ReadPlan(regions: regions)
    }

    /// The old text outside the changed parts, then the new text read inside them.
    func merge(previous: [RecognizedLine], recognized: [RecognizedLine]) -> [RecognizedLine] {
        let kept = previous.filter { line in !regions.contains { $0.core.intersects(line.box) } }
        let read = recognized.filter { line in
            let center = CGPoint(x: line.box.midX, y: line.box.midY)
            return regions.contains { $0.core.contains(center) }
        }
        return kept + read
    }

    /// The rectangles around groups of changed tiles that lie within reach of each other.
    private static func changedParts(_ changed: [Bool], signature: TileSignature) -> [CGRect] {
        var visited = [Bool](repeating: false, count: changed.count)
        var parts: [CGRect] = []
        for start in changed.indices where changed[start] && !visited[start] {
            visited[start] = true
            var stack = [start]
            var part = CGRect.null
            while let index = stack.popLast() {
                let column = index % signature.columns
                let row = index / signature.columns
                part = part.union(signature.rect(column: column, row: row))
                for rowStep in -joinDistanceTiles...joinDistanceTiles {
                    for columnStep in -joinDistanceTiles...joinDistanceTiles {
                        let nextColumn = column + columnStep
                        let nextRow = row + rowStep
                        guard (0..<signature.columns).contains(nextColumn),
                            (0..<signature.rows).contains(nextRow)
                        else { continue }
                        let next = nextRow * signature.columns + nextColumn
                        guard changed[next], !visited[next] else { continue }
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }
            parts.append(part)
        }
        return merged(parts)
    }

    /// Joins the two rectangles whose union adds the least area, so distant changes stay apart.
    private static func joiningNearestPair(of rects: [CGRect]) -> [CGRect] {
        var best: (first: Int, second: Int, added: CGFloat)?
        for first in rects.indices {
            for second in rects.indices where second > first {
                let union = rects[first].union(rects[second])
                let added =
                    union.width * union.height - rects[first].width * rects[first].height
                    - rects[second].width * rects[second].height
                if added < (best?.added ?? .infinity) { best = (first, second, added) }
            }
        }
        guard let best else { return rects }
        var joined = rects
        joined[best.first] = rects[best.first].union(rects[best.second])
        joined.remove(at: best.second)
        return joined
    }

    /// Joins rectangles that overlap until none do.
    private static func merged(_ rects: [CGRect]) -> [CGRect] {
        var rects = rects
        var index = 0
        while index < rects.count {
            if let other = rects.indices.first(where: { $0 != index && rects[$0].intersects(rects[index]) }) {
                rects[min(index, other)] = rects[index].union(rects[other])
                rects.remove(at: max(index, other))
                index = 0
            } else {
                index += 1
            }
        }
        return rects
    }
}
