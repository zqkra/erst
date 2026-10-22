import ErstModel
import SwiftUI

/// The first dock row: the source column, the time block over the playhead, and the actions.
struct TimelineDockHeader: View {
    let model: TimelineModel
    let onOpenMoment: (Moment) -> Void

    var body: some View {
        TimelineDockHeaderLayout(rowHeight: TimelineMetrics.headerHeight) {
            TimelineDockSource(model: model)
            TimelineDockTime(model: model)
            TimelineDateControl(model: model)
            TimelineDockActions(model: model, onOpenMoment: onOpenMoment)
        }
    }
}

/// Centers the time block (clock and date) over the playhead, places the source before
/// it, and the actions at the trailing edge.
private struct TimelineDockHeaderLayout: Layout {
    let rowHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard subviews.count == 4 else { return }
        let centerX = bounds.minX + TimelineMetrics.trackCenterX(rowWidth: bounds.width)
        let timeSize = subviews[1].sizeThatFits(.unspecified)
        let actionsSize = subviews[3].sizeThatFits(.unspecified)
        let dateMetrics = subviews[2].dimensions(in: .unspecified)
        let blockWidth = timeSize.width + TimelineMetrics.timeGap + dateMetrics.width
        let timeX = centerX - blockWidth / 2
        let sourceWidth = max(0, timeX - bounds.minX - TimelineMetrics.sourceGap)
        let timeMetrics = subviews[1].dimensions(in: .unspecified)
        let timeHeight = max(1, timeMetrics.height)
        let baselineY = bounds.midY - timeHeight / 2 + timeMetrics[.firstTextBaseline]
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
            proposal: ProposedViewSize(width: sourceWidth, height: rowHeight))
        subviews[1].place(
            at: CGPoint(x: timeX, y: baselineY),
            anchor: UnitPoint(x: 0, y: timeMetrics[.firstTextBaseline] / timeHeight),
            proposal: ProposedViewSize(width: timeSize.width, height: timeSize.height))
        let dateHeight = max(1, dateMetrics.height)
        subviews[2].place(
            at: CGPoint(x: timeX + timeSize.width + TimelineMetrics.timeGap, y: baselineY),
            anchor: UnitPoint(x: 0, y: dateMetrics[.firstTextBaseline] / dateHeight),
            proposal: ProposedViewSize(
                width: dateMetrics.width, height: dateMetrics.height))
        subviews[3].place(
            at: CGPoint(x: bounds.maxX - actionsSize.width, y: bounds.midY), anchor: .leading,
            proposal: ProposedViewSize(width: actionsSize.width, height: rowHeight))
    }
}

private struct TimelineDockSource: View {
    let model: TimelineModel

    var body: some View {
        HStack(spacing: TimelineMetrics.sourceIconGap) {
            if let segment = model.selectedSegment {
                TimelineAppIcon(
                    app: segment.app, size: TimelineMetrics.sourceIconSize,
                    cornerRadius: TimelineMetrics.sourceIconCornerRadius)
                VStack(alignment: .leading, spacing: TimelineMetrics.sourceTextGap) {
                    Text(WindowTitle.clean(segment.title, appName: segment.app.name) ?? segment.app.name)
                        .erstStyle(TimelineType.sourceTitle)
                        .foregroundStyle(Color.erstText)
                        .lineLimit(1)
                    Text(segment.host ?? segment.app.name)
                        .erstStyle(TimelineType.sourceSubtitle)
                        .foregroundStyle(Color.erstSecondary)
                        .lineLimit(1)
                }
                .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct TimelineDockTime: View {
    let model: TimelineModel

    var body: some View {
        Text(TimelineFormat.clock(model.selectedDate))
            .erstStyle(TimelineType.clock)
            .foregroundStyle(Color.erstText)
            .fixedSize()
    }
}

private struct TimelineDockActions: View {
    let model: TimelineModel
    let onOpenMoment: (Moment) -> Void

    var body: some View {
        HStack(spacing: TimelineMetrics.actionsGap) {
            TimelineActionButton(
                symbol: "square.on.square", help: "Copy image",
                isEnabled: model.image != nil
            ) {
                model.copyImage()
            }
            TimelineActionButton(
                symbol: "text.viewfinder", help: "Select text",
                isEnabled: model.canOpenMoment
            ) {
                guard let moment = model.selectedMoment else { return }
                onOpenMoment(moment)
            }
            TimelineActionButton(
                symbol: "arrow.up.forward.app", help: "Open in app",
                isEnabled: model.canOpenMoment
            ) {
                model.openSource()
            }
        }
        .padding(.horizontal, TimelineMetrics.actionsCapsulePadding)
        .frame(height: TimelineMetrics.actionsCapsuleHeight)
        .background(Capsule(style: .continuous).fill(TimelineStyle.actionsFill))
    }
}
