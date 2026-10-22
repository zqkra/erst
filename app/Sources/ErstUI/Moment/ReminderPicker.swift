import SwiftUI

/// A small date sheet for a reminder.
public struct ReminderPicker: View {
    let model: MomentModel
    @Environment(\.dismiss) private var dismiss
    private let pickerWidthPoints: CGFloat = 380

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            Text("Remind me")
                .erstStyle(Typography.title)
                .foregroundStyle(Color.erstText)
            DatePicker(
                "When",
                selection: Binding(get: { model.reminderDate }, set: { model.reminderDate = $0 }),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            HStack(spacing: Spacing.small) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                Button("Set reminder") {
                    model.remind(at: model.reminderDate)
                    dismiss()
                }
                .prominentAction()
            }
        }
        .font(Typography.body.font)
        .padding(Spacing.xxLarge)
        .frame(width: pickerWidthPoints)
        .windowMaterial()
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }
}
