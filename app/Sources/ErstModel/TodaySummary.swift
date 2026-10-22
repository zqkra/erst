import Foundation

/// The compact numbers the menu bar shows for the current day.
public struct TodaySummary: Hashable, Sendable {
    /// Local midnight to the moment the summary was read. `heat` spreads its buckets evenly over it.
    public let range: ClosedRange<Date>
    public let onScreen: TimeInterval
    public let keptBytes: Int64
    public let heat: [UInt8]
    public let topApps: [AppTotal]

    public init(
        range: ClosedRange<Date>, onScreen: TimeInterval, keptBytes: Int64, heat: [UInt8],
        topApps: [AppTotal]
    ) {
        self.range = range
        self.onScreen = onScreen
        self.keptBytes = keptBytes
        self.heat = heat
        self.topApps = topApps
    }
}
