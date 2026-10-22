import AppKit
import ErstModel
import SwiftUI

/// The Month scale's track: a column per day and a row per hour, colored by heat.
///
/// A click points at an hour and the frame from it fills the screen; a second click on the same
/// hour opens its frames at 1h. Scrolling sideways steps days, and up or down steps hours.
struct TimelineMonthGrid: NSViewRepresentable {
    let model: TimelineModel

    func makeNSView(context: Context) -> TimelineMonthGridView {
        let view = TimelineMonthGridView(frame: .zero)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Activity this month by day and hour")
        return view
    }

    func updateNSView(_ view: TimelineMonthGridView, context: Context) {
        view.state = Self.state(of: model.month, now: model.referenceDate)
        view.setAccessibilityValue(view.state?.cursorText)
        view.describe = { [month = model.month] cell in
            month.hourStart(day: cell.day, hour: cell.hour).map(TimelineFormat.monthCursor) ?? ""
        }
        view.onPick = { [model] cell, isRepeat in
            if isRepeat {
                model.openMonthHour()
            } else if let date = model.month.hourStart(day: cell.day, hour: cell.hour) {
                model.pointMonth(at: date)
            }
        }
        view.onStep = { [model] days, hours in
            model.stepMonth(days: days, hours: hours)
        }
    }

    @MainActor
    private static func state(of month: TimelineMonth, now: Date) -> TimelineMonthGridState {
        let calendar = Calendar.current
        let dayCount = month.dayCount
        let start = month.interval?.start ?? now
        let days = (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let nowCell = month.interval.map { interval -> TimelineMonthCell in
            guard interval.contains(now) else {
                return now < interval.start
                    ? TimelineMonthCell(day: -1, hour: 0)
                    : TimelineMonthCell(day: dayCount, hour: 0)
            }
            let day = calendar.dateComponents([.day], from: interval.start, to: now).day ?? 0
            return TimelineMonthCell(day: day, hour: calendar.component(.hour, from: now))
        }
        return TimelineMonthGridState(
            title: TimelineFormat.monthTitle(start),
            cursorText: month.cursor.map { TimelineFormat.monthCursor($0.start) } ?? "",
            dayCount: dayCount,
            levels: month.days.map(\.hours),
            cursor: month.cursorCell.map { TimelineMonthCell(day: $0.day, hour: $0.hour) },
            today: days.firstIndex { calendar.isDate($0, inSameDayAs: now) },
            weekendDays: Set(days.indices.filter { calendar.isDateInWeekend(days[$0]) }),
            lastPastCell: nowCell)
    }
}

/// Paints the month and turns pointer and scroll input into cells and steps.
final class TimelineMonthGridView: NSView {
    var state: TimelineMonthGridState? {
        didSet { if state != oldValue { needsDisplay = true } }
    }
    var onPick: ((TimelineMonthCell, Bool) -> Void)?
    /// The hour a cell stands for, shown while the pointer is over it.
    var describe: ((TimelineMonthCell) -> String)?
    var onStep: ((Int, Int) -> Void)?

    private var hover: TimelineMonthCell? {
        didSet { if hover != oldValue { needsDisplay = true } }
    }
    private var scrollDays: CGFloat = 0
    private var scrollHours: CGFloat = 0

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var layout: TimelineMonthLayout {
        TimelineMonthLayout(size: bounds.size, dayCount: state?.dayCount ?? 0)
    }

    // MARK: Input

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        hover = layout.cell(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let cell = layout.cell(at: convert(event.locationInWindow, from: nil)) else { return }
        onPick?(cell, cell == state?.cursor || event.clickCount > 1)
    }

    /// Precise deltas accumulate into whole steps. A mouse wheel moves one hour a notch, and
    /// Shift turns it sideways into days, as macOS does for horizontal scrolling.
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began {
            scrollDays = 0
            scrollHours = 0
        }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : TimelineMetrics.monthScrollPointsPerHour
        scrollDays -= event.scrollingDeltaX * scale / TimelineMetrics.monthScrollPointsPerDay
        scrollHours -= event.scrollingDeltaY * scale / TimelineMetrics.monthScrollPointsPerHour
        let days = Int(scrollDays.rounded(.towardZero))
        let hours = Int(scrollHours.rounded(.towardZero))
        guard days != 0 || hours != 0 else { return }
        scrollDays -= CGFloat(days)
        scrollHours -= CGFloat(hours)
        onStep?(days, hours)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let state, let context = NSGraphicsContext.current?.cgContext else { return }
        let layout = layout
        drawHeader(state)
        for day in 0..<state.dayCount {
            if day == state.cursor?.day {
                fill(layout.columnHighlight(day), TimelineTrackStyle.monthColumnSelected, in: context)
            } else if day == hover?.day {
                fill(layout.columnHighlight(day), TimelineTrackStyle.monthColumnHover, in: context)
            }
            drawColumn(day, state: state, layout: layout, in: context)
            drawLabel(day, state: state, layout: layout)
        }
        if let hover, hover != state.cursor {
            ring(
                layout.cell(hover), TimelineTrackStyle.monthHoverRing, TimelineMetrics.monthHoverRingWidth,
                in: context)
        }
        if let cursor = state.cursor {
            let cell = layout.cell(cursor)
            ring(
                cell, TimelineTrackStyle.monthCursorOutline, TimelineMetrics.monthCursorOutlineWidth,
                in: context)
            ring(cell, TimelineTrackStyle.butter, TimelineMetrics.monthCursorRingWidth, in: context)
        }
    }

    private func drawHeader(_ state: TimelineMonthGridState) {
        let title = NSAttributedString(string: state.title, attributes: TimelineTrackStyle.chipNameAttributes)
        title.draw(at: .zero)
        let text = hover.flatMap { describe?($0) } ?? state.cursorText
        let cursor = NSAttributedString(string: text, attributes: TimelineTrackStyle.chipDetailAttributes)
        cursor.draw(at: CGPoint(x: bounds.width - cursor.size().width, y: 0))
    }

    /// Every hour of a day, clipped to one rounded column so the day reads as a single bar. Hours
    /// with the same shade draw as one block, so a busy stretch has no seams.
    private func drawColumn(
        _ day: Int, state: TimelineMonthGridState, layout: TimelineMonthLayout, in context: CGContext
    ) {
        let column = layout.column(day)
        let radius = min(TimelineMetrics.monthColumnCornerRadius, column.width / 2)
        context.saveGState()
        context.addPath(
            CGPath(roundedRect: column, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        var hour = 0
        while hour < TimelineMonthCell.hoursPerDay {
            let color = shade(TimelineMonthCell(day: day, hour: hour), state: state)
            var end = hour + 1
            while end < TimelineMonthCell.hoursPerDay,
                shade(TimelineMonthCell(day: day, hour: end), state: state) == color
            {
                end += 1
            }
            context.setFillColor(color.cgColor)
            context.fill(layout.hours(day: day, from: hour, to: end))
            hour = end
        }
        context.restoreGState()
    }

    /// The heat color of an hour, or the faded quiet color for an hour still to come.
    private func shade(_ cell: TimelineMonthCell, state: TimelineMonthGridState) -> NSColor {
        let palette = TimelineTrackStyle.heatLevels
        if let last = state.lastPastCell, cell.isAfter(last) {
            return TimelineTrackStyle.monthFuture
        }
        let levels = state.levels.indices.contains(cell.day) ? state.levels[cell.day] : []
        let level = levels.indices.contains(cell.hour) ? Int(levels[cell.hour]) : 0
        return palette[min(level, palette.count - 1)]
    }

    private func drawLabel(_ day: Int, state: TimelineMonthGridState, layout: TimelineMonthLayout) {
        let isSelected = day == state.cursor?.day
        guard isSelected || layout.showsLabel(day) else { return }
        let label = NSAttributedString(
            string: "\(day + 1)",
            attributes: TimelineTrackStyle.monthDayAttributes(
                isSelected: isSelected, isToday: day == state.today,
                isWeekend: state.weekendDays.contains(day)))
        let center = layout.dayLabelCenter(day)
        label.draw(at: CGPoint(x: center.x - label.size().width / 2, y: center.y))
    }

    private func fill(_ rect: CGRect, _ color: NSColor, in context: CGContext) {
        let radius = TimelineMetrics.monthColumnHighlightCornerRadius
        context.setFillColor(color.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
    }

    private func ring(_ cell: CGRect, _ color: NSColor, _ width: CGFloat, in context: CGContext) {
        let outset = TimelineMetrics.monthCursorRingOutset
        let rect = cell.insetBy(dx: -outset, dy: -outset)
        let radius = min(rect.height / 2, TimelineMetrics.monthColumnCornerRadius)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.strokePath()
    }
}
