import CoreGraphics
import Foundation

/// The Month scale: the grid picks an hour, and the frame closest to its middle fills the screen.
extension TimelineModel {
    /// Points the month at the hour containing `date`, never past now, and shows the frame closest
    /// to the middle of that hour. That frame lies inside the hour whenever the hour has one.
    public func pointMonth(at date: Date) {
        month.point(at: min(date, referenceDate))
        guard let hour = month.cursor else { return }
        let middle = min(hour.start.addingTimeInterval(hour.duration / 2), referenceDate)
        if let track, let day = calendar.dateInterval(of: .day, for: middle),
            track.range.lowerBound <= day.start,
            track.range.upperBound >= min(day.end, referenceDate),
            let index = track.nearestIndex(to: middle)
        {
            select(index: index)
            return
        }
        load(dayRange(around: middle), selecting: middle, after: Self.monthLoadDelay)
    }

    /// Moves the month's hour by whole days and hours, keeping the other on the wall clock.
    public func stepMonth(days: Int, hours: Int) {
        guard let date = month.cursorDate(movedByDays: days, hours: hours) else { return }
        pointMonth(at: date)
    }

    /// Leaves the month for the frames of the hour it points at, once they are loaded.
    public func openMonthHour() {
        let pending = loadTask
        Task { [weak self] in
            await pending?.value
            guard let self else { return }
            self.setScale(.hour, trackWidth: self.trackWidth)
        }
    }

    /// Scrubbing through days starts a load per day; waiting this long keeps only the last.
    private static let monthLoadDelay = Duration.milliseconds(80)

    /// The day holding `date` and the day before it, so one step back needs no load.
    private func dayRange(around date: Date) -> ClosedRange<Date> {
        let dayStart = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        return start...max(start, min(end, referenceDate))
    }
}
