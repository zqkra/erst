import SwiftUI

/// Back, time, and neighbor navigation above the frame.
public struct MomentHeader: View {
    let model: MomentModel
    let onOpenTimeline: (Date) -> Void
    let onClose: () -> Void
    private let headerHeightPoints: CGFloat = 52

    public var body: some View {
        HStack(spacing: Spacing.large) {
            Button(action: onClose) {
                HStack(spacing: Spacing.small) {
                    Image(systemName: "chevron.left")
                        .font(Typography.tiny.font)
                    Text("Back")
                        .erstStyle(Typography.captionMedium)
                }
                .foregroundStyle(Color.erstText)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .erstCapsule()
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: Spacing.xSmall) {
                Text(ErstFormat.clock(model.currentMoment.capturedAt))
                    .erstStyle(Typography.clock)
                    .foregroundStyle(Color.erstText)
                Text(ErstFormat.day(model.currentMoment.capturedAt))
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstSecondary)
            }
            .fixedSize()

            GlassEffectContainer(spacing: Spacing.small) {
                HStack(spacing: Spacing.small) {
                    Button("Timeline") {
                        onOpenTimeline(model.currentMoment.capturedAt)
                    }
                    .font(Typography.captionMedium.font)
                    .glassAction()
                    CircleGlassButton(
                        symbol: "chevron.left",
                        help: "Previous moment",
                        isEnabled: model.previousMoment != nil,
                        action: model.goPrevious
                    )
                    CircleGlassButton(
                        symbol: "chevron.right",
                        help: "Next moment",
                        isEnabled: model.nextMoment != nil,
                        action: model.goNext
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: headerHeightPoints)
    }
}
