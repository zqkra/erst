import ErstModel
import SwiftUI

/// The dock: source, time and actions above the scrollable track and the zoom column.
struct TimelineDock: View {
    let model: TimelineModel
    let onOpenMoment: (Moment) -> Void

    var body: some View {
        VStack(spacing: TimelineMetrics.dockRowGap) {
            TimelineDockHeader(model: model, onOpenMoment: onOpenMoment)
                .frame(height: TimelineMetrics.headerHeight)
            TimelineTrackRow(model: model)
                .frame(height: TimelineMetrics.trackHeight)
        }
        .padding(.top, TimelineMetrics.dockPaddingTop)
        .padding(.horizontal, TimelineMetrics.dockPaddingHorizontal)
        .padding(.bottom, TimelineMetrics.dockPaddingBottom)
        .frame(height: TimelineMetrics.dockHeight, alignment: .top)
        .timelineDockSurface()
    }
}
