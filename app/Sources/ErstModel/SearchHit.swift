import Foundation

/// A group of nearby moments that matched the same search, represented by its best frame.
public struct SearchHit: Hashable, Identifiable, Sendable {
    public let moment: Moment
    public let matchedLines: [TextLine]
    public let firstSeen: Date
    public let lastSeen: Date

    public var id: Int64 { moment.id }

    public init(moment: Moment, matchedLines: [TextLine], firstSeen: Date, lastSeen: Date) {
        self.moment = moment
        self.matchedLines = matchedLines
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}
