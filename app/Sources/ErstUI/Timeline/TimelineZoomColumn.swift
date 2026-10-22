import SwiftUI

/// The scale presets and the Now button, bottom aligned with the track.
struct TimelineZoomColumn: View {
    let model: TimelineModel
    let trackWidth: CGFloat

    var body: some View {
        VStack(spacing: TimelineMetrics.zoomGap) {
            TimelineScaleControl(model: model, trackWidth: trackWidth)
            nowButton
        }
        .frame(width: TimelineMetrics.zoomColumnWidth)
    }

    private var nowButton: some View {
        Button {
            model.goNow()
        } label: {
            Text("Now")
                .erstStyle(TimelineType.now)
                .foregroundStyle(Color.erstInk)
                .frame(maxWidth: .infinity)
                .frame(height: TimelineMetrics.scaleHeight)
                .background(Capsule(style: .continuous).fill(Color.erstButter))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canGoNow)
        .opacity(model.canGoNow ? 1 : TimelineMetrics.nowOpacityWhenDisabled)
        .help("Go to the newest frame")
    }
}

private struct TimelineScaleControl: View {
    let model: TimelineModel
    let trackWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TimelineScale.allCases) { scale in
                Button {
                    model.setScale(scale, trackWidth: trackWidth)
                } label: {
                    label(for: scale)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(TimelineMetrics.scalePadding)
        .frame(height: TimelineMetrics.scaleHeight)
        .background(
            RoundedRectangle(
                cornerRadius: TimelineMetrics.scaleCornerRadius, style: .continuous
            ).fill(TimelineStyle.scaleFill))
    }

    private func label(for scale: TimelineScale) -> some View {
        let selected = model.activeScale == scale
        return Text(scale.title)
            .erstStyle(selected ? TimelineType.scaleSelected : TimelineType.scale)
            .foregroundStyle(selected ? Color.white : TimelineStyle.scaleText)
            .frame(maxWidth: .infinity)
            .frame(height: TimelineMetrics.scaleHeight - TimelineMetrics.scalePadding * 2)
            .background {
                if selected {
                    RoundedRectangle(
                        cornerRadius: TimelineMetrics.scalePillCornerRadius, style: .continuous
                    )
                    .fill(TimelineStyle.scalePill)
                    .shadow(
                        color: .black.opacity(TimelineMetrics.scalePillShadowOpacity),
                        radius: TimelineMetrics.scalePillShadowRadius,
                        y: TimelineMetrics.scalePillShadowY)
                }
            }
            .contentShape(Rectangle())
    }
}
