import SwiftUI

/// Period control and a date stepper.
public struct ActivityToolbar: View {
    let model: ActivityModel
    private let pickerWidthPoints: CGFloat = 240
    private let stepButtonSizePoints: CGFloat = 20
    private let dateMinimumWidthPoints: CGFloat = 96
    private let toolbarHeightPoints: CGFloat = 30
    private let backwardStepCount = -1
    private let forwardStepCount = 1

    public var body: some View {
        HStack(spacing: Spacing.large) {
            Picker("Period", selection: Binding(get: { model.period }, set: model.setPeriod)) {
                ForEach(ActivityModel.Period.allCases) { period in
                    Text(period.title).erstStyle(Typography.body).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: pickerWidthPoints)

            Spacer(minLength: Spacing.large)

            HStack(spacing: Spacing.small) {
                Button {
                    model.step(backwardStepCount)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(Typography.tiny.font)
                        .foregroundStyle(Color.erstText)
                        .frame(width: stepButtonSizePoints, height: stepButtonSizePoints)
                }
                .buttonStyle(.plain)
                .help("Previous period")

                Text(model.stepperTitle)
                    .erstStyle(Typography.captionMedium)
                    .foregroundStyle(Color.erstText)
                    .frame(minWidth: dateMinimumWidthPoints)

                Button {
                    model.step(forwardStepCount)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(Typography.tiny.font)
                        .foregroundStyle(
                            model.canGoForward ? Color.erstText : Color.erstSecondary
                        )
                        .frame(width: stepButtonSizePoints, height: stepButtonSizePoints)
                }
                .buttonStyle(.plain)
                .disabled(!model.canGoForward)
                .help("Next period")
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .background {
                Capsule(style: .continuous).fill(Color.erstSurface)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.erstHairline, lineWidth: ControlMetrics.hairlinePoints)
                    // A stroked capsule leaves a vertical sliver at each end, so the stroke
                    // is clipped to the capsule to keep one even border all the way around.
                    .clipShape(Capsule(style: .continuous))
            }
        }
        .frame(height: toolbarHeightPoints)
    }
}
