import CoreGraphics
import Foundation

/// What the month grid draws, resolved from the model so the view only paints it.
struct TimelineMonthGridState: Equatable {
    let title: String
    let cursorText: String
    let dayCount: Int
    /// Levels per day, 24 each, empty while the month loads.
    let levels: [[UInt8]]
    let cursor: TimelineMonthCell?
    let today: Int?
    let weekendDays: Set<Int>
    /// Cells after this one have not happened yet.
    let lastPastCell: TimelineMonthCell?
}

/// One hour of one day of the month, both counted from zero.
struct TimelineMonthCell: Equatable {
    let day: Int
    let hour: Int

    static let hoursPerDay = 24

    func isAfter(_ other: TimelineMonthCell) -> Bool {
        day > other.day || (day == other.day && hour > other.hour)
    }
}

/// Where each day and hour of the month sits in the track, and which cell a point falls in.
struct TimelineMonthLayout {
    let size: CGSize
    let dayCount: Int

    var columnWidth: CGFloat {
        dayCount > 0 ? size.width / CGFloat(dayCount) : 0
    }

    private var rowHeight: CGFloat {
        (TimelineMetrics.monthGridBottom - TimelineMetrics.monthGridTop)
            / CGFloat(TimelineMonthCell.hoursPerDay)
    }

    private var cellGap: CGFloat {
        max(TimelineMetrics.monthCellMinimumGap, columnWidth * TimelineMetrics.monthCellGapFraction)
    }

    /// The heat area of one day, every hour stacked in it.
    func column(_ day: Int) -> CGRect {
        CGRect(
            x: CGFloat(day) * columnWidth + cellGap / 2, y: TimelineMetrics.monthGridTop,
            width: max(1, columnWidth - cellGap),
            height: TimelineMetrics.monthGridBottom - TimelineMetrics.monthGridTop)
    }

    /// The wider band behind a highlighted day.
    func columnHighlight(_ day: Int) -> CGRect {
        let inset = TimelineMetrics.monthColumnHighlightInset
        return CGRect(
            x: CGFloat(day) * columnWidth + 1, y: TimelineMetrics.monthGridTop - inset,
            width: max(1, columnWidth - 2),
            height: TimelineMetrics.monthGridBottom - TimelineMetrics.monthGridTop + inset * 2)
    }

    func cell(_ cell: TimelineMonthCell) -> CGRect {
        hours(day: cell.day, from: cell.hour, to: cell.hour + 1)
    }

    /// The hours `from..<to` of one day as one block, so equal neighbours draw without seams.
    func hours(day: Int, from: Int, to: Int) -> CGRect {
        let column = column(day)
        return CGRect(
            x: column.minX, y: column.minY + CGFloat(from) * rowHeight,
            width: column.width, height: CGFloat(to - from) * rowHeight)
    }

    /// The center of a day's number under its column.
    func dayLabelCenter(_ day: Int) -> CGPoint {
        CGPoint(x: (CGFloat(day) + 0.5) * columnWidth, y: TimelineMetrics.hourLabelTop)
    }

    /// Whether a day gets its number: every day when there is room, else the odd dates.
    func showsLabel(_ day: Int) -> Bool {
        columnWidth >= TimelineMetrics.monthDayLabelMinimumSpacing || day % 2 == 0
    }

    /// The cell under a point. Points above or below the grid take the nearest hour.
    func cell(at point: CGPoint) -> TimelineMonthCell? {
        guard dayCount > 0, columnWidth > 0, point.x >= 0, point.x < size.width else { return nil }
        let day = min(dayCount - 1, Int(point.x / columnWidth))
        let row = Int(((point.y - TimelineMetrics.monthGridTop) / rowHeight).rounded(.down))
        return TimelineMonthCell(day: day, hour: min(max(row, 0), TimelineMonthCell.hoursPerDay - 1))
    }
}
