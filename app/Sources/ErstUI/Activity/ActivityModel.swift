import Combine
import ErstModel
import Foundation
import Observation
import SwiftUI

/// A label under the chart at a fractional position.
public struct ActivityChartLabel: Identifiable, Sendable {
    public let fraction: CGFloat
    public let text: String

    public var id: String { "\(fraction)-\(text)" }
}

/// State for the day, week, and month activity report.
@MainActor
@Observable
// ObservableObject supports StateObject ownership with the Command Line Tools SDK.
public final class ActivityModel: ObservableObject {
    public enum Period: String, CaseIterable, Identifiable, Sendable {
        case day
        case week
        case month

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .day: "Day"
            case .week: "Week"
            case .month: "Month"
            }
        }
    }

    public private(set) var period: Period = .day
    public private(set) var anchor = Date()
    public private(set) var report: ActivityReport?

    private let service: any MemoryService
    private var hasLoaded = false
    private let comparisonToleranceSeconds: TimeInterval = 60
    private let secondsPerMinute: TimeInterval = 60
    private let minutesPerHour = 60
    private let dayStepCount = 1
    private let dayLabelIntervalHours = 6
    private let hoursPerDay = 24
    private let monthLabelIntervalDays = 7
    private let bucketCenterFraction: CGFloat = 0.5
    @ObservationIgnored private var fetchTask: Task<Void, Never>?

    public init(service: any MemoryService, period: Period = .day) {
        self.service = service
        self.period = period
    }

    public var range: ClosedRange<Date> {
        let calendar = Calendar.current
        switch period {
        case .day:
            let start = calendar.startOfDay(for: anchor)
            let end = calendar.date(byAdding: .day, value: dayStepCount, to: start) ?? anchor
            return start...end
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) else {
                return anchor...anchor
            }
            return interval.start...interval.end
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: anchor) else {
                return anchor...anchor
            }
            return interval.start...interval.end
        }
    }

    public var dateLine: String {
        switch period {
        case .day:
            return ErstFormat.day(anchor)
        case .week:
            return Calendar.current.isDate(anchor, equalTo: Date(), toGranularity: .weekOfYear)
                ? "This week" : "Week of \(ErstFormat.shortDate(range.lowerBound))"
        case .month:
            return Calendar.current.isDate(anchor, equalTo: Date(), toGranularity: .month)
                ? "This month" : ErstFormat.month(anchor)
        }
    }

    public var stepperTitle: String {
        switch period {
        case .day: ErstFormat.shortDate(anchor)
        case .week: "Week of \(ErstFormat.shortDate(range.lowerBound))"
        case .month: ErstFormat.month(anchor)
        }
    }

    public var totalText: String {
        ErstFormat.duration(report?.total ?? 0)
    }

    public var comparisonText: String {
        guard let report, let previous = report.previousTotal else { return "No earlier data to compare" }
        let difference = report.total - previous
        if abs(difference) < comparisonToleranceSeconds {
            return "About the same as \(comparisonWord)"
        }
        let minutes = Int((abs(difference) / secondsPerMinute).rounded())
        let amount = minutes < minutesPerHour ? "\(minutes) minutes" : ErstFormat.duration(abs(difference))
        return "\(amount) \(difference < 0 ? "less" : "more") than \(comparisonWord)"
    }

    public var canGoForward: Bool {
        range.upperBound <= Date()
    }

    public func categoryTotal(_ category: ActivityCategory) -> TimeInterval {
        report?.categories[category] ?? 0
    }

    public var chartBuckets: [ActivityBucket] {
        report?.buckets ?? []
    }

    public var chartLabels: [ActivityChartLabel] {
        guard let report, !report.buckets.isEmpty else { return [] }
        switch report.bucketKind {
        case .hour:
            return stride(from: 0, through: hoursPerDay, by: dayLabelIntervalHours).map { hour in
                ActivityChartLabel(
                    fraction: CGFloat(hour) / CGFloat(hoursPerDay),
                    text: String(format: "%02d:00", hour)
                )
            }
        case .day:
            return period == .month
                ? monthLabels(for: report.buckets)
                : weekdayLabels(for: report.buckets)
        }
    }

    private func weekdayLabels(for buckets: [ActivityBucket]) -> [ActivityChartLabel] {
        buckets.enumerated().map { index, bucket in
            let weekday = Calendar.current.component(.weekday, from: bucket.start)
            return ActivityChartLabel(
                fraction: (CGFloat(index) + bucketCenterFraction) / CGFloat(buckets.count),
                text: ErstFormat.weekdayShort(weekday)
            )
        }
    }

    private func monthLabels(for buckets: [ActivityBucket]) -> [ActivityChartLabel] {
        stride(from: 0, to: buckets.count, by: monthLabelIntervalDays).map { index in
            ActivityChartLabel(
                fraction: (CGFloat(index) + bucketCenterFraction) / CGFloat(buckets.count),
                text: "\(Calendar.current.component(.day, from: buckets[index].start))"
            )
        }
    }

    public func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await fetch()
    }

    public func setPeriod(_ period: Period) {
        guard period != self.period else { return }
        self.period = period
        reload()
    }

    public func step(_ direction: Int) {
        let calendar = Calendar.current
        switch period {
        case .day:
            anchor = calendar.date(byAdding: .day, value: direction, to: anchor) ?? anchor
        case .week:
            anchor = calendar.date(byAdding: .weekOfYear, value: direction, to: anchor) ?? anchor
        case .month:
            anchor = calendar.date(byAdding: .month, value: direction, to: anchor) ?? anchor
        }
        reload()
    }

    private func reload() {
        fetchTask?.cancel()
        report = nil
        fetchTask = Task { [weak self] in await self?.fetch() }
    }

    private func fetch() async {
        let requestedRange = range
        let report = try? await service.activity(in: requestedRange)
        guard !Task.isCancelled, requestedRange == range else { return }
        self.report = report
    }

    private var comparisonWord: String {
        switch period {
        case .day: "yesterday"
        case .week: "last week"
        case .month: "last month"
        }
    }
}

extension ActivityCategory {
    public var color: Color {
        switch self {
        case .building: .erstButter
        case .reading: .erstOrange
        case .talking: .erstCoral
        case .other: .erstSecondary
        }
    }
}
