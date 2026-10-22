import ErstModel
import Foundation
import Observation

/// The calendar month the timeline shows at the Month scale: hourly heat for each of its days and
/// the hour the user points at.
@MainActor
@Observable
public final class TimelineMonth {
    public private(set) var interval: DateInterval?
    /// One entry per local day of `interval`, empty while it loads.
    public private(set) var days: [DayHeat] = []
    /// The hour the user points at.
    public private(set) var cursor: DateInterval?

    private let service: any MemoryService
    private let calendar = Calendar.current
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(service: any MemoryService) {
        self.service = service
    }

    /// The days in the month shown, 28 to 31.
    public var dayCount: Int {
        guard let interval else { return 0 }
        return calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 0
    }

    /// Points at the hour containing `date`, and loads its month when the month changes.
    func point(at date: Date) {
        guard let hour = calendar.dateInterval(of: .hour, for: date),
            let month = calendar.dateInterval(of: .month, for: date)
        else { return }
        cursor = hour
        guard month != interval else { return }
        interval = month
        days = []
        loadTask?.cancel()
        loadTask = Task { [weak self, service] in
            let loaded = (try? await service.hourlyHeat(in: month.start...month.end)) ?? []
            guard !Task.isCancelled, let self, self.interval == month else { return }
            self.days = loaded
        }
    }

    /// The cursor moved by whole days and hours on the wall clock.
    func cursorDate(movedByDays days: Int, hours: Int) -> Date? {
        guard let cursor,
            let shifted = calendar.date(byAdding: .day, value: days, to: cursor.start)
        else { return nil }
        return calendar.date(byAdding: .hour, value: hours, to: shifted)
    }

    /// The start of wall-clock `hour` on day `day` of the month, both counted from zero.
    public func hourStart(day: Int, hour: Int) -> Date? {
        guard let interval,
            let dayStart = calendar.date(byAdding: .day, value: day, to: interval.start)
        else { return nil }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart)
    }

    /// The cursor's day and hour, both counted from zero.
    public var cursorCell: (day: Int, hour: Int)? {
        guard let interval, let cursor, interval.contains(cursor.start) else { return nil }
        let day = calendar.dateComponents([.day], from: interval.start, to: cursor.start).day ?? 0
        return (day, calendar.component(.hour, from: cursor.start))
    }
}
