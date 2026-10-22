import SwiftUI

/// Open, copy, and remind, in one full-width row at the bottom of the inspector.
public struct MomentActions: View {
    let model: MomentModel
    @Environment(\.erstOpaquePanels) private var opaquePanels
    /// The bell's box inside the glass circle, so the circle is as tall as the large buttons.
    private let reminderIconSizePoints: CGFloat = 16

    public var body: some View {
        HStack(spacing: Spacing.small) {
            Button {
                model.openPage()
            } label: {
                label(model.primaryActionTitle)
            }
            .prominentAction()

            Button {
                model.copyText()
            } label: {
                label("Copy text")
            }
            .glassAction()

            reminderMenu
        }
        .controlSize(.extraLarge)
        .font(Typography.bodyMedium.font)
    }

    /// The two text actions share the row's width equally, so the row reads as one control.
    private func label(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    private var reminderMenu: some View {
        Menu {
            Button("Later today") { model.remindLaterToday() }
            Button("Tomorrow morning") { model.remindTomorrow() }
            Button("Next week") { model.remindNextWeek() }
            Divider()
            Button("Pick a date...") { model.reminderPickerPresented = true }
        } label: {
            Image(systemName: "bell")
                .font(Typography.icon.font)
                .frame(width: reminderIconSizePoints, height: reminderIconSizePoints)
                .background {
                    if opaquePanels {
                        Circle().fill(Color.erstSurface)
                    }
                }
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .menuIndicator(.hidden)
        .help("Remind me")
        .accessibilityLabel("Remind me")
    }
}
