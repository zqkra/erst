import ErstModel
import SwiftUI

/// The date in the time block. Clicking it opens the date jump popover.
struct TimelineDateControl: View {
    let model: TimelineModel
    private let popoverWidthPoints: CGFloat = 300

    var body: some View {
        Button {
            model.setChoosingDate(true)
        } label: {
            Text(TimelineFormat.date(model.selectedDate))
                .erstStyle(TimelineType.date)
                .foregroundStyle(Color.erstSecondary)
                .fixedSize()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { model.isChoosingDate }, set: { model.setChoosingDate($0) }),
            arrowEdge: .bottom
        ) {
            TimelineDatePopover(model: model)
                .frame(width: popoverWidthPoints)
        }
        .help("Jump to a date")
    }
}

/// The calendar and the two quick choices.
private struct TimelineDatePopover: View {
    let model: TimelineModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            HStack(spacing: Spacing.small) {
                quickChoice("Today") { model.jumpToToday() }
                quickChoice("Yesterday") { model.jumpToYesterday() }
            }
            DatePicker(
                "Date",
                selection: Binding(
                    get: { model.selectedDate },
                    set: { model.jump(to: $0) }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        }
        .padding(Spacing.large)
    }

    private func quickChoice(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .erstStyle(Typography.captionMedium)
                .foregroundStyle(Color.erstText)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Capsule(style: .continuous).fill(Color.erstSurface))
    }
}
