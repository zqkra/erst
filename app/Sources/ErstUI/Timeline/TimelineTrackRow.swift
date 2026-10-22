import SwiftUI

/// The second dock row: the scrolling track under its fixed playhead, and the zoom column.
struct TimelineTrackRow: View {
    let model: TimelineModel

    var body: some View {
        GeometryReader { proxy in
            let width = max(
                0,
                proxy.size.width - TimelineMetrics.zoomColumnWidth - TimelineMetrics.trackZoomGap)
            HStack(alignment: .top, spacing: TimelineMetrics.trackZoomGap) {
                track(width: width)
                TimelineZoomColumn(model: model, trackWidth: width)
                    .frame(
                        width: TimelineMetrics.zoomColumnWidth,
                        height: TimelineMetrics.trackHeight, alignment: .bottom)
            }
        }
        .frame(height: TimelineMetrics.trackHeight)
    }

    @ViewBuilder
    private func track(width: CGFloat) -> some View {
        if model.activeScale == .month {
            TimelineMonthGrid(model: model)
                .frame(width: width, height: TimelineMetrics.trackHeight)
        } else {
            frames(width: width)
        }
    }

    private func frames(width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            TimelineTrackScroller(
                track: model.track,
                pointsPerFrame: model.pointsPerFrame,
                selectedIndex: model.selectedIndex,
                scrollGeneration: model.scrollGeneration,
                onScrollSelect: { index in
                    Task { @MainActor in model.reportScrolledIndex(index) }
                },
                onClickSelect: { index in
                    Task { @MainActor in model.select(index: index) }
                },
                onVisibleLowerChange: { lower in
                    Task { @MainActor in model.prefetchIfNeeded(visibleLowerBound: lower) }
                },
                onZoom: { factor, index in
                    model.zoom(by: factor, keeping: index)
                }
            )
            .frame(width: width, height: TimelineMetrics.trackHeight)
            playhead
        }
        .frame(width: width, height: TimelineMetrics.trackHeight)
        .clipped()
    }

    private var playhead: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: TimelineMetrics.playheadCornerRadius, style: .continuous)
                .fill(Color.erstButter)
                .frame(
                    width: TimelineMetrics.playheadLineWidth,
                    height: TimelineMetrics.playheadLineHeight
                )
                .offset(y: TimelineMetrics.playheadLineTop)
            Circle()
                .fill(Color.erstButter)
                .frame(
                    width: TimelineMetrics.playheadKnobSize,
                    height: TimelineMetrics.playheadKnobSize
                )
                .overlay {
                    Circle()
                        .stroke(
                            TimelineStyle.playheadRing,
                            lineWidth: TimelineMetrics.playheadRingWidth)
                }
                .offset(y: TimelineMetrics.playheadKnobTop)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }
}
