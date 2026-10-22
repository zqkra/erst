import Foundation

/// One local day of hourly heat, the way the timeline's month draws it.
public struct DayHeat: Hashable, Sendable {
    /// Local midnight, or the requested range's start for the first day.
    public let start: Date
    /// The next local midnight, or the requested range's end for the last day.
    public let end: Date
    /// Levels 0...5 for the 24 wall-clock hours, midnight first, scaled against the busiest hour
    /// of the whole request so that days compare.
    public let hours: [UInt8]

    public init(start: Date, end: Date, hours: [UInt8]) {
        self.start = start
        self.end = end
        self.hours = hours
    }
}
