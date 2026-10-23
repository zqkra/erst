import ErstModel
import Foundation

/// A deterministic sample of app visits and kept frames, built around one anchor date.
struct PreviewDataset: Sendable {
    let now: Date
    let today: Date
    let spans: [PreviewSpan]
    let moments: [PreviewMomentRecord]
    private let hourBucketRangeLimitSeconds: TimeInterval = 3 * 24 * 60 * 60
    private let bucketLimitCount = 4_096

    init(now: Date, includesHistory: Bool = true) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        self.now = now
        self.today = today
        guard includesHistory else {
            spans = []
            moments = []
            return
        }
        var allSpans: [PreviewSpan] = []
        for offset in -70...0 {
            allSpans += PreviewSchedule.spans(dayOffset: offset, today: today, now: now)
        }
        spans = allSpans
        moments = PreviewSchedule.moments(spans: allSpans)
    }

    private init(now: Date, today: Date, spans: [PreviewSpan], moments: [PreviewMomentRecord]) {
        self.now = now
        self.today = today
        self.spans = spans
        self.moments = moments
    }

    func erasing(_ range: ClosedRange<Date>) -> PreviewDataset {
        let remainingSpans = spans.filter { !$0.range.overlaps(range) }
        let spanIDs = Set(remainingSpans.map(\.id))
        let remainingMoments = moments.filter { record in
            spanIDs.contains(record.span.id) && !range.contains(record.moment.capturedAt)
        }
        return PreviewDataset(
            now: now,
            today: today,
            spans: remainingSpans,
            moments: remainingMoments
        )
    }

    func timeline(in range: ClosedRange<Date>, buckets: Int) -> TimelineSlice {
        let bucketCount = max(1, buckets)
        let bucketWidth = range.upperBound.timeIntervalSince(range.lowerBound) / Double(bucketCount)
        let overlapping = spans(overlapping: range)
        let visible = moments(in: range).map {
            MomentStamp(id: $0.moment.id, capturedAt: $0.moment.capturedAt)
        }
        var heat = [UInt8](repeating: 0, count: bucketCount)
        for index in 0..<bucketCount {
            let start = range.lowerBound.addingTimeInterval(Double(index) * bucketWidth)
            let end = index == bucketCount - 1 ? range.upperBound : start.addingTimeInterval(bucketWidth)
            let bucket = start...end
            let active = overlapping.filter { $0.range.overlaps(bucket) }
            guard !active.isEmpty else { continue }
            let momentCount = visible.filter { bucket.contains($0.capturedAt) }.count
            let appCount = Set(active.map(\.app.bundleID)).count
            heat[index] = UInt8(min(5, 2 + min(2, momentCount) + (appCount > 1 ? 1 : 0)))
        }
        let segments = overlapping.map { span in
            AppSegment(
                id: span.id,
                app: span.app,
                windowTitle: span.windowTitle,
                range: span.range.clamped(to: range)
            )
        }
        return TimelineSlice(range: range, heat: heat, segments: segments, moments: visible)
    }

    /// One row of 24 hours per local day, each with the synthetic level `timeline` gives it.
    func hourlyHeat(in range: ClosedRange<Date>) -> [DayHeat] {
        let calendar = Calendar.current
        var days: [DayHeat] = []
        var start = range.lowerBound
        while start < range.upperBound {
            let midnight = calendar.startOfDay(for: start)
            let next = calendar.date(byAdding: .day, value: 1, to: midnight) ?? range.upperBound
            let end = min(next, range.upperBound)
            let hours = (0..<24).map { hour -> UInt8 in
                guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: midnight),
                    let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart)
                else { return 0 }
                let lower = max(hourStart, start)
                let upper = min(hourEnd, end)
                guard lower < upper else { return 0 }
                return timeline(in: lower...upper, buckets: 1).heat.first ?? 0
            }
            days.append(DayHeat(start: start, end: end, hours: hours))
            start = end
        }
        return days
    }

    func moment(id: Moment.ID) -> PreviewMomentRecord? {
        moments.first { $0.moment.id == id }
    }

    func nearest(to date: Date) -> Moment? {
        moments.min {
            abs($0.moment.capturedAt.timeIntervalSince(date))
                < abs($1.moment.capturedAt.timeIntervalSince(date))
        }?.moment
    }

    func detail(for moment: Moment) -> MomentDetail? {
        guard let record = self.moment(id: moment.id),
            let index = moments.firstIndex(where: { $0.moment.id == moment.id })
        else { return nil }
        let sameWindow = spans.filter {
            $0.app.bundleID == record.span.app.bundleID && $0.windowTitle == record.span.windowTitle
        }
        let visits = sameWindow.filter {
            Calendar.current.isDate($0.range.lowerBound, inSameDayAs: moment.capturedAt)
        }.count
        let lastOpened =
            sameWindow
            .map(\.range.lowerBound)
            .filter { $0 <= moment.capturedAt }
            .max()
        let lower = max(0, index - 8)
        let upper = min(moments.count - 1, index + 8)
        let neighbors = moments[lower...upper]
            .filter { $0.moment.id != moment.id }
            .map(\.moment)
        return MomentDetail(
            moment: moment,
            lines: record.lines,
            onScreen: record.span.range,
            visitsToday: max(1, visits),
            lastOpened: lastOpened,
            neighbors: neighbors
        )
    }

    func search(_ query: SearchQuery, limit: Int) -> [SearchHit] {
        let terms = query.text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        let candidates = moments.filter { record in
            if let app = query.app, record.moment.app.bundleID != app.bundleID { return false }
            if let range = query.range, !range.contains(record.moment.capturedAt) { return false }
            return true
        }
        let matches: [(record: PreviewMomentRecord, lines: [TextLine])] = candidates.compactMap { record in
            let matchedLines = record.lines.filter { line in
                terms.contains { line.text.localizedCaseInsensitiveContains($0) }
            }
            let allPresent = terms.allSatisfy { term in
                record.lines.contains { $0.text.localizedCaseInsensitiveContains(term) }
            }
            return allPresent && !matchedLines.isEmpty ? (record, matchedLines) : nil
        }
        var hits: [SearchHit] = []
        for match in matches {
            let moment = match.record.moment
            if let last = hits.last,
                last.moment.app.bundleID == moment.app.bundleID,
                last.moment.windowTitle == moment.windowTitle,
                moment.capturedAt.timeIntervalSince(last.lastSeen) <= 600
            {
                let isBetter = match.lines.count > last.matchedLines.count
                hits[hits.count - 1] = SearchHit(
                    moment: isBetter ? moment : last.moment,
                    matchedLines: isBetter ? match.lines : last.matchedLines,
                    firstSeen: last.firstSeen,
                    lastSeen: moment.capturedAt
                )
            } else {
                hits.append(
                    SearchHit(
                        moment: moment,
                        matchedLines: match.lines,
                        firstSeen: moment.capturedAt,
                        lastSeen: moment.capturedAt
                    )
                )
            }
        }
        return Array(hits.reversed().prefix(max(0, limit)))
    }

    func activity(in range: ClosedRange<Date>) -> ActivityReport {
        let clipped = spans(overlapping: range).map { ($0, $0.range.clamped(to: range)) }
        var categories: [ActivityCategory: TimeInterval] = [:]
        var appDurations: [String: (AppRef, TimeInterval)] = [:]
        var siteDurations: [String: TimeInterval] = [:]
        var total: TimeInterval = 0
        for (span, spanRange) in clipped {
            let duration = spanRange.upperBound.timeIntervalSince(spanRange.lowerBound)
            guard duration > 0 else { continue }
            total += duration
            categories[PreviewCategory.of(span.app), default: 0] += duration
            appDurations[span.app.bundleID, default: (span.app, 0)].1 += duration
            if let host = PreviewSiteHost.host(span.url) {
                siteDurations[host, default: 0] += duration
            }
        }
        let apps = appDurations.values
            .map { AppTotal(app: $0.0, duration: $0.1) }
            .sorted { $0.duration > $1.duration }
        let websites =
            siteDurations
            .map { SiteTotal(host: $0.key, duration: $0.value) }
            .sorted { $0.duration > $1.duration }
        let length = range.upperBound.timeIntervalSince(range.lowerBound)
        let previousRange = range.lowerBound.addingTimeInterval(-length)...range.lowerBound
        let previous = spans(overlapping: previousRange)
            .map { $0.range.clamped(to: previousRange) }
            .reduce(TimeInterval(0)) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) }
        let bucketPlan = activityBuckets(in: range, spans: clipped)
        return ActivityReport(
            range: range,
            total: total,
            previousTotal: previous > 0 ? previous : nil,
            categories: categories,
            bucketKind: bucketPlan.kind,
            buckets: bucketPlan.buckets,
            apps: apps,
            websites: websites
        )
    }

    /// Midnight to now in 48 buckets, the way the live service reads today.
    func todaySummary() -> TodaySummary {
        let dayRange = today...max(today, now)
        let report = activity(in: dayRange)
        let keptToday = moments(in: dayRange).count
        return TodaySummary(
            range: dayRange,
            onScreen: report.total,
            keptBytes: Int64(keptToday) * 320_000,
            heat: timeline(in: dayRange, buckets: 48).heat,
            topApps: Array(report.apps.prefix(3))
        )
    }

    private func moments(in range: ClosedRange<Date>) -> [PreviewMomentRecord] {
        moments.filter { range.contains($0.moment.capturedAt) }
    }

    private func spans(overlapping range: ClosedRange<Date>) -> [PreviewSpan] {
        spans.filter { $0.range.overlaps(range) }
    }

    /// Buckets the way the engine does: hours for up to three days, then local days.
    private func activityBuckets(
        in range: ClosedRange<Date>,
        spans: [(PreviewSpan, ClosedRange<Date>)]
    ) -> (kind: ActivityBucketKind, buckets: [ActivityBucket]) {
        let calendar = Calendar.current
        let duration = range.upperBound.timeIntervalSince(range.lowerBound)
        let kind: ActivityBucketKind = duration <= hourBucketRangeLimitSeconds ? .hour : .day
        let component: Calendar.Component = kind == .hour ? .hour : .day
        var starts: [Date] = []
        var cursor = range.lowerBound
        while cursor < range.upperBound, starts.count < bucketLimitCount {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor
            else { break }
            cursor = min(next, range.upperBound)
        }
        let ends = starts.indices.map { index in
            index + 1 < starts.count ? starts[index + 1] : range.upperBound
        }
        var totals = [[ActivityCategory: TimeInterval]](repeating: [:], count: starts.count)
        for (span, spanRange) in spans {
            let category = PreviewCategory.of(span.app)
            for index in starts.indices {
                let start = max(starts[index], spanRange.lowerBound)
                let end = min(ends[index], spanRange.upperBound)
                guard end > start else { continue }
                totals[index][category, default: 0] += end.timeIntervalSince(start)
            }
        }
        let buckets = starts.indices.map { index in
            ActivityBucket(start: starts[index], end: ends[index], byCategory: totals[index])
        }
        return (kind, buckets)
    }
}

enum PreviewCategory {
    static func of(_ app: AppRef) -> ActivityCategory {
        switch app.bundleID {
        case PreviewApps.zed.bundleID, PreviewApps.ghostty.bundleID: .building
        case PreviewApps.mail.bundleID, PreviewApps.slack.bundleID: .talking
        case PreviewApps.safari.bundleID, PreviewApps.x.bundleID: .reading
        default: .other
        }
    }
}

private extension ClosedRange {
    func clamped(to other: ClosedRange<Bound>) -> ClosedRange<Bound> {
        let lower = Swift.max(lowerBound, other.lowerBound)
        let upper = Swift.min(upperBound, other.upperBound)
        return lower...Swift.max(lower, upper)
    }
}
