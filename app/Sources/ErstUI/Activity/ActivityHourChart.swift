import ErstModel
import SwiftUI

/// Capsule bars stacked by category, one per hour or day.
public struct ActivityHourChart: View {
    private let buckets: [ActivityBucket]
    private let labels: [ActivityChartLabel]

    private let plotHeightPoints: CGFloat = 190
    private let labelHeightPoints: CGFloat = 16
    private let labelEdgeInsetPoints: CGFloat = 20
    private let labelCenterYPoints: CGFloat = 8
    private let maximumBarWidthPoints: CGFloat = 48
    private let minimumBarWidthPoints: CGFloat = 8
    private let barWidthFraction: CGFloat = 0.6
    private let minimumBarHeightPoints: CGFloat = 1
    private let minimumScaleSeconds: TimeInterval = 1
    private let centerDivisor: CGFloat = 2
    private let categories: [ActivityCategory] = [.building, .reading, .talking, .other]

    public init(buckets: [ActivityBucket], labels: [ActivityChartLabel]) {
        self.buckets = buckets
        self.labels = labels
    }

    public var body: some View {
        GeometryReader { proxy in
            VStack(spacing: Spacing.small) {
                Canvas { context, size in
                    drawBars(context: context, size: size)
                }
                .frame(height: plotHeightPoints)
                ZStack(alignment: .topLeading) {
                    ForEach(labels) { label in
                        Text(label.text)
                            .erstStyle(Typography.caption)
                            .foregroundStyle(Color.erstSecondary)
                            .position(
                                x: min(
                                    max(label.fraction * proxy.size.width, labelEdgeInsetPoints),
                                    proxy.size.width - labelEdgeInsetPoints),
                                y: labelCenterYPoints
                            )
                    }
                }
                .frame(height: labelHeightPoints)
            }
        }
        .overlay {
            if !buckets.contains(where: { $0.total > 0 }) {
                Text("No activity in this range")
                    .erstStyle(Typography.body)
                    .foregroundStyle(Color.erstSecondary)
            }
        }
    }

    private func drawBars(context: GraphicsContext, size: CGSize) {
        guard !buckets.isEmpty else { return }
        let chartHeight = size.height
        let step = size.width / CGFloat(buckets.count)
        let barWidth = min(maximumBarWidthPoints, max(minimumBarWidthPoints, step * barWidthFraction))
        let maxTotal = max(minimumScaleSeconds, buckets.map(\.total).max() ?? 0)
        for (index, bucket) in buckets.enumerated() {
            let height = chartHeight * CGFloat(bucket.total / maxTotal)
            guard height > minimumBarHeightPoints else { continue }
            let x = CGFloat(index) * step + (step - barWidth) / centerDivisor
            let rect = CGRect(x: x, y: chartHeight - height, width: barWidth, height: height)
            var barContext = context
            barContext.clip(
                to: Path(roundedRect: rect, cornerRadius: min(Radius.bar, barWidth / centerDivisor)))
            var bottom = chartHeight
            for category in categories {
                let duration = bucket.byCategory[category] ?? 0
                guard duration > 0 else { continue }
                let segmentHeight = chartHeight * CGFloat(duration / maxTotal)
                let segment = CGRect(
                    x: x,
                    y: bottom - segmentHeight,
                    width: barWidth,
                    height: segmentHeight
                )
                barContext.fill(Path(segment), with: .color(category.color))
                bottom -= segmentHeight
            }
        }
    }
}
