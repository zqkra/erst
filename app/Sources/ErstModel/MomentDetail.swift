import Foundation

/// Everything the moment inspector needs about a single kept frame.
public struct MomentDetail: Hashable, Sendable {
    public let moment: Moment
    public let lines: [TextLine]
    public let onScreen: ClosedRange<Date>?
    public let visitsToday: Int
    public let lastOpened: Date?
    public let neighbors: [Moment]

    public init(
        moment: Moment,
        lines: [TextLine],
        onScreen: ClosedRange<Date>?,
        visitsToday: Int,
        lastOpened: Date?,
        neighbors: [Moment]
    ) {
        self.moment = moment
        self.lines = lines
        self.onScreen = onScreen
        self.visitsToday = visitsToday
        self.lastOpened = lastOpened
        self.neighbors = neighbors
    }
}
