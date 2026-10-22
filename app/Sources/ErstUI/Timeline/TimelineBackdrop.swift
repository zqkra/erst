import SwiftUI

/// The top and bottom scrims that keep the dock and the search capsule legible.
struct TimelineBackdrop: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(
                        color: Color.erstGround.opacity(TimelineMetrics.topScrimOpacity),
                        location: 0),
                    .init(color: Color.erstGround.opacity(0), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: TimelineMetrics.topScrimHeight)
            Spacer(minLength: 0)
            LinearGradient(
                stops: [
                    .init(color: Color.erstGround.opacity(0), location: 0),
                    .init(
                        color: Color.erstGround.opacity(TimelineMetrics.bottomScrimMiddleOpacity),
                        location: TimelineMetrics.bottomScrimMiddleLocation),
                    .init(
                        color: Color.erstGround.opacity(TimelineMetrics.bottomScrimOpacity),
                        location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: TimelineMetrics.bottomScrimHeight)
        }
        .allowsHitTesting(false)
    }
}

/// The quiet state before anything has been recorded.
struct TimelineEmptyState: View {
    private let markSizePoints: CGFloat = 44

    var body: some View {
        VStack(spacing: Spacing.large) {
            ErstMark()
                .fill(Color.erstButter)
                .frame(width: markSizePoints, height: markSizePoints)
            Text("Nothing recorded yet")
                .erstStyle(Typography.body)
                .foregroundStyle(Color.erstSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
