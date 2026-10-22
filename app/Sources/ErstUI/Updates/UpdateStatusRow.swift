import ErstModel
import SwiftUI

/// The update in Settings, About: what Erst is doing, what changed, and the one action that fits.
struct UpdateStatusRow: View {
    let updates: SoftwareUpdateModel

    var body: some View {
        let copy = UpdateStatusCopy(phase: updates.phase)
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(spacing: Spacing.medium) {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(copy.title)
                        .erstStyle(Typography.bodyMedium)
                        .foregroundStyle(Color.erstText)
                    if let detail = copy.detail {
                        Text(detail)
                            .erstStyle(Typography.caption)
                            .foregroundStyle(Color.erstSecondary)
                    }
                }
                Spacer(minLength: Spacing.small)
                action
            }
            if let progress = copy.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.erstButter)
            }
            if !copy.notes.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    ForEach(copy.notes, id: \.self) { note in
                        Text(note)
                            .erstStyle(Typography.body)
                            .foregroundStyle(Color.erstSecondary)
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xSmall)
    }

    @ViewBuilder
    private var action: some View {
        switch updates.phase {
        case .upToDate, .failed:
            Button("Check Now") { updates.actions.check() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .checking, .preparing, .installing:
            ProgressView()
                .controlSize(.small)
        case .available:
            primary("Update and Relaunch")
        case .downloading:
            Button("Cancel") { updates.actions.cancel() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .ready:
            primary("Relaunch to Update")
        }
    }

    private func primary(_ title: String) -> some View {
        Button {
            updates.actions.install()
        } label: {
            Text(title)
                .erstStyle(Typography.bodyMedium)
        }
        .prominentAction()
        .controlSize(.small)
    }
}

/// The updates section of Settings, About.
struct UpdatesSection: View {
    let updates: SoftwareUpdateModel

    var body: some View {
        Section {
            UpdateStatusRow(updates: updates)
            Toggle("Check for updates automatically", isOn: updates.checksBinding)
            Toggle("Download and install updates automatically", isOn: updates.installsBinding)
                .disabled(!updates.checksAutomatically)
        } header: {
            Text("Updates")
        } footer: {
            Text(
                "Updates come from Erst's releases on GitHub. Each one is checked against Erst's "
                    + "signature before it installs."
            )
            .erstStyle(Typography.caption)
            .foregroundStyle(Color.erstSecondary)
        }
    }
}
