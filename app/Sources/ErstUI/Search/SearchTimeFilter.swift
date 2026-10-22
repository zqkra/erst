import Foundation

/// The time scopes offered next to the search field.
public enum SearchTimeFilter: String, CaseIterable, Identifiable, Sendable {
    case anyTime
    case today
    case yesterday
    case last7Days
    case last30Days

    public var id: String { rawValue }
    private var yesterdayOffsetDays: Int { -1 }
    private var weekOffsetDays: Int { -7 }
    private var monthOffsetDays: Int { -30 }
    private var timestampResolutionSeconds: TimeInterval { 0.001 }

    public var title: String {
        switch self {
        case .anyTime: "Any time"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        }
    }

    /// The range the engine should search, or `nil` for all history.
    public func range(now: Date = Date()) -> ClosedRange<Date>? {
        let calendar = Calendar.current
        switch self {
        case .anyTime:
            return nil
        case .today:
            let start = calendar.startOfDay(for: now)
            return start...max(start, now)
        case .yesterday:
            guard
                let start = calendar.date(
                    byAdding: .day, value: yesterdayOffsetDays, to: calendar.startOfDay(for: now))
            else { return nil }
            let end = calendar.startOfDay(for: now).addingTimeInterval(-timestampResolutionSeconds)
            return start...end
        case .last7Days:
            guard let start = calendar.date(byAdding: .day, value: weekOffsetDays, to: now) else {
                return nil
            }
            return start...now
        case .last30Days:
            guard let start = calendar.date(byAdding: .day, value: monthOffsetDays, to: now) else {
                return nil
            }
            return start...now
        }
    }
}
