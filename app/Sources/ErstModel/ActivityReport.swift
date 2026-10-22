import Foundation

/// The four kinds of work Erst groups app time into.
public enum ActivityCategory: CaseIterable, Codable, Hashable, Sendable {
    case building
    case reading
    case talking
    case other

    public var displayName: String {
        switch self {
        case .building: "Building"
        case .reading: "Reading"
        case .talking: "Talking"
        case .other: "Other"
        }
    }
}

/// Time spent in one app during a range.
public struct AppTotal: Hashable, Identifiable, Sendable {
    public let app: AppRef
    public let duration: TimeInterval

    public var id: String { app.bundleID }

    public init(app: AppRef, duration: TimeInterval) {
        self.app = app
        self.duration = duration
    }
}

/// Time spent on one website host during a range.
public struct SiteTotal: Hashable, Identifiable, Sendable {
    public let host: String
    public let duration: TimeInterval

    public var id: String { host }

    public init(host: String, duration: TimeInterval) {
        self.host = host
        self.duration = duration
    }
}

/// The width of one activity bucket.
public enum ActivityBucketKind: Hashable, Sendable {
    /// One hour, unaffected by daylight saving.
    case hour
    /// One local day, from one local midnight to the next.
    case day
}

/// Category totals for one bucket of the activity chart.
///
/// A bucket covers `[start, end)`. Day buckets follow local midnights, so a day
/// with a daylight saving change is 23 or 25 hours long.
public struct ActivityBucket: Hashable, Identifiable, Sendable {
    public let start: Date
    public let end: Date
    public let byCategory: [ActivityCategory: TimeInterval]

    public var id: Date { start }

    public var total: TimeInterval {
        byCategory.values.reduce(0, +)
    }

    public init(start: Date, end: Date, byCategory: [ActivityCategory: TimeInterval]) {
        self.start = start
        self.end = end
        self.byCategory = byCategory
    }
}

/// How a range of time was spent, with the comparison the activity screen shows.
public struct ActivityReport: Hashable, Sendable {
    public let range: ClosedRange<Date>
    public let total: TimeInterval
    public let previousTotal: TimeInterval?
    public let categories: [ActivityCategory: TimeInterval]
    public let bucketKind: ActivityBucketKind
    public let buckets: [ActivityBucket]
    public let apps: [AppTotal]
    public let websites: [SiteTotal]

    public init(
        range: ClosedRange<Date>,
        total: TimeInterval,
        previousTotal: TimeInterval?,
        categories: [ActivityCategory: TimeInterval],
        bucketKind: ActivityBucketKind,
        buckets: [ActivityBucket],
        apps: [AppTotal],
        websites: [SiteTotal]
    ) {
        self.range = range
        self.total = total
        self.previousTotal = previousTotal
        self.categories = categories
        self.bucketKind = bucketKind
        self.buckets = buckets
        self.apps = apps
        self.websites = websites
    }
}
