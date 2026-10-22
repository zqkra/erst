import ErstModel
import SwiftUI

/// What the moment is, how long it was on screen, and what text it held. The text can expand to
/// fill the inspector, folding the title and details away.
public struct MomentInspector: View {
    let model: MomentModel
    private let dividerHeightPoints: CGFloat = 1
    private let appIconSizePoints: CGFloat = 18
    private let titleLineCount = 2
    /// Critically damped: the panel folds without bouncing, and quickly, since it is a tool.
    private let expandAnimation = Animation.spring(duration: 0.32, bounce: 0)

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            if !model.isTextExpanded {
                Group {
                    title
                        .erstArrival(3)
                    rows
                        .erstArrival(4)
                    Rectangle()
                        .fill(Color.erstHairline)
                        .frame(height: dividerHeightPoints)
                }
                .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                textHeader
                MomentText(lines: model.detail?.lines ?? [], highlightedTerms: model.highlightedTerms)
            }
            .erstArrival(5, blurs: false)
            MomentActions(model: model)
        }
        .padding(Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Radius.inspector, style: .continuous)
                .fill(Color.erstControlScrim)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.inspector, style: .continuous)
                .strokeBorder(Color.erstHairline, lineWidth: ControlMetrics.hairlinePoints)
        }
    }

    private var textHeader: some View {
        HStack(spacing: Spacing.small) {
            Text("Text on screen")
                .erstStyle(Typography.eyebrow)
                .foregroundStyle(Color.erstSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if !(model.detail?.lines.isEmpty ?? true) {
                MomentExpandButton(isExpanded: model.isTextExpanded) {
                    withAnimation(expandAnimation) { model.toggleTextExpanded() }
                }
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(titleText)
                .erstStyle(Typography.panelTitle)
                .foregroundStyle(Color.erstText)
                .lineLimit(titleLineCount)
            HStack(spacing: Spacing.small) {
                AppIconView(app: model.currentMoment.app, size: appIconSizePoints)
                Text(model.currentMoment.app.name)
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstSecondary)
                if model.hostText != model.currentMoment.app.name {
                    Text(model.hostText)
                        .erstStyle(Typography.caption)
                        .foregroundStyle(Color.erstSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var titleText: String {
        WindowTitle.clean(
            model.currentMoment.windowTitle, appName: model.currentMoment.app.name)
            ?? model.currentMoment.app.name
    }

    private var rows: some View {
        VStack(spacing: Spacing.small) {
            MomentInfoRow(label: "On screen", value: model.onScreenText)
            MomentInfoRow(label: "Visits today", value: "\(model.detail?.visitsToday ?? 0)")
            MomentInfoRow(label: "Last opened", value: model.lastOpenedText)
        }
    }
}

/// Expands the text over the inspector, or folds it back.
private struct MomentExpandButton: View {
    let isExpanded: Bool
    let action: () -> Void
    private let sizePoints: CGFloat = 22

    var body: some View {
        Button(action: action) {
            Image(
                systemName: isExpanded
                    ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            )
            .font(Typography.caption.font)
            .foregroundStyle(Color.erstSecondary)
            .frame(width: sizePoints, height: sizePoints)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Show details" : "Expand text")
        .accessibilityLabel(isExpanded ? "Show details" : "Expand text")
    }
}
