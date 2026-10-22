import SwiftUI

/// Today's heat above a continuous hairline, leaving unrecorded time empty, with the hours under
/// it so a bar reads as a time of day.
struct MenuBarHeatStrip: View {
    let heat: [UInt8]
    /// Midnight to now. Without it the strip draws no hours.
    let range: ClosedRange<Date>?
    private let stripHeightPoints: CGFloat = 28
    private let axisHeightPoints: CGFloat = 12
    private let minimumBarWidthPoints: CGFloat = 1
    private let barWidthFraction: CGFloat = 0.74
    private let centerDivisor: CGFloat = 2
    private let levelHeightFractions: [CGFloat] = [0, 0.28, 0.44, 0.62, 0.82, 1]
    private let levelColors: [Color] = [
        .erstTrack, .erstHeatOne, .erstHeatTwo, .erstCoral, .erstOrange, .erstButter,
    ]
    private let hoursPerLabel = 6
    private let hoursPerDay = 24
    /// The least space between one hour label and the next, or "Now".
    private let labelGapPoints: CGFloat = 8

    var body: some View {
        VStack(spacing: Spacing.xSmall) {
            bars
            axis
        }
        .accessibilityElement()
        .accessibilityLabel("Today's screen activity")
    }

    private var bars: some View {
        Canvas { context, size in
            let baseline = CGRect(
                x: 0, y: size.height - ControlMetrics.hairlinePoints,
                width: size.width, height: ControlMetrics.hairlinePoints
            )
            context.fill(Path(baseline), with: .color(.erstHairline))
            guard !heat.isEmpty else { return }
            let step = size.width / CGFloat(heat.count)
            let width = min(step, max(minimumBarWidthPoints, step * barWidthFraction))
            for (index, level) in heat.enumerated() where level > 0 {
                let colorIndex = min(Int(level), levelColors.count - 1)
                let height = size.height * levelHeightFractions[colorIndex]
                let rect = CGRect(
                    x: CGFloat(index) * step + (step - width) / centerDivisor,
                    y: size.height - height, width: width, height: height
                )
                let path = Path(roundedRect: rect, cornerRadius: min(Radius.bar, width / centerDivisor))
                context.fill(path, with: .color(levelColors[colorIndex]))
            }
        }
        .frame(height: stripHeightPoints)
    }

    /// Every sixth hour starts its label at its own x, and "Now" closes the strip on the right.
    /// An hour label that would run into the next one, or into "Now", is left out.
    private var axis: some View {
        Canvas { context, size in
            guard let range else { return }
            let now = context.resolve(label("Now"))
            let nowWidth = now.measure(in: size).width
            context.draw(now, at: CGPoint(x: size.width, y: 0), anchor: .topTrailing)
            let duration = range.upperBound.timeIntervalSince(range.lowerBound)
            guard duration > 0 else { return }
            let calendar = Calendar.current
            let midnight = calendar.startOfDay(for: range.lowerBound)
            var limit = size.width - nowWidth - labelGapPoints
            for hour in stride(from: 0, to: hoursPerDay, by: hoursPerLabel).reversed() {
                guard let date = calendar.date(byAdding: .hour, value: hour, to: midnight) else {
                    continue
                }
                let fraction = date.timeIntervalSince(range.lowerBound) / duration
                guard fraction >= 0, fraction < 1 else { continue }
                let text = context.resolve(label(TimelineFormat.hourText(hour)))
                let x = size.width * fraction
                let width = text.measure(in: size).width
                guard x + width <= limit else { continue }
                context.draw(text, at: CGPoint(x: x, y: 0), anchor: .topLeading)
                limit = x - labelGapPoints
            }
        }
        .frame(height: axisHeightPoints)
    }

    private func label(_ text: String) -> Text {
        Text(text)
            .font(Typography.tiny.font)
            .foregroundStyle(Color.erstSecondary)
    }
}
