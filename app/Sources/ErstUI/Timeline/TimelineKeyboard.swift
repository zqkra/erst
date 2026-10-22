import ErstModel
import SwiftUI

/// The timeline's keys. Arrows step frames, Shift steps segments, Return opens the frame, and
/// Command-plus and Command-minus zoom. At the Month scale the arrows step days and hours, Shift
/// steps weeks, and Return opens the hour. Command-K and / open search; while it is open, the
/// keys belong to it.
struct TimelineKeyboard: ViewModifier {
    let model: TimelineModel
    let search: TimelineSearchPresentation
    let onOpenMoment: (Moment) -> Void
    let onClose: () -> Void

    private let daysPerWeek = 7

    private var isMonth: Bool { model.activeScale == .month }

    func body(content: Content) -> some View {
        content
            .onKeyPress(.leftArrow, phases: .down) { press in
                step(by: -1, press: press)
            }
            .onKeyPress(.rightArrow, phases: .down) { press in
                step(by: 1, press: press)
            }
            .onKeyPress(.upArrow, phases: .down) { _ in
                guard !search.isPresented, isMonth else { return .ignored }
                model.stepMonth(days: 0, hours: -1)
                return .handled
            }
            .onKeyPress(.downArrow, phases: .down) { _ in
                guard !search.isPresented, isMonth else { return .ignored }
                model.stepMonth(days: 0, hours: 1)
                return .handled
            }
            .onKeyPress(.return) {
                guard !search.isPresented else { return .ignored }
                if isMonth {
                    model.openMonthHour()
                    return .handled
                }
                guard let moment = model.selectedMoment else { return .ignored }
                onOpenMoment(moment)
                return .handled
            }
            .onKeyPress(characters: ["+", "="], phases: .down) { press in
                zoom(by: TimelineMetrics.zoomStep, press: press)
            }
            .onKeyPress("-", phases: .down) { press in
                zoom(by: 1 / TimelineMetrics.zoomStep, press: press)
            }
            .onKeyPress("k", phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                search.toggle()
                return .handled
            }
            .onKeyPress("/", phases: .down) { _ in
                guard !search.isPresented else { return .ignored }
                search.open()
                return .handled
            }
            .onKeyPress(.escape) {
                if search.isPresented {
                    search.close()
                } else {
                    onClose()
                }
                return .handled
            }
    }

    private func step(by direction: Int, press: KeyPress) -> KeyPress.Result {
        guard !search.isPresented else { return .ignored }
        let shifted = press.modifiers.contains(.shift)
        if isMonth {
            model.stepMonth(days: direction * (shifted ? daysPerWeek : 1), hours: 0)
        } else if shifted {
            model.stepSegment(by: direction)
        } else {
            model.step(by: direction)
        }
        return .handled
    }

    private func zoom(by factor: CGFloat, press: KeyPress) -> KeyPress.Result {
        guard !search.isPresented, !isMonth, press.modifiers.contains(.command) else {
            return .ignored
        }
        model.zoom(by: factor, keeping: model.selectedIndex)
        return .handled
    }
}
