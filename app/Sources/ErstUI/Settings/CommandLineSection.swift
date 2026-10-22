import ErstModel
import SwiftUI

/// The `erst` command: whether a terminal finds it, one button to fix that, and what to type.
struct CommandLineSection: View {
    let model: SettingsModel

    private static let examples: [(command: String, meaning: String)] = [
        ("erst search invoice today", "Find something you saw today"),
        ("erst activity", "Time per app, site, and kind of work today"),
        ("erst stats", "Storage used and frames kept"),
    ]

    var body: some View {
        Section {
            HStack(spacing: Spacing.medium) {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text("erst command")
                        .erstStyle(Typography.body)
                        .foregroundStyle(Color.erstText)
                    Text(status)
                        .erstStyle(Typography.caption)
                        .foregroundStyle(Color.erstSecondary)
                }
                Spacer(minLength: Spacing.small)
                if model.isChangingCommandLine {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: model.changeCommandLine) {
                        Text(actionTitle)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            ForEach(Self.examples, id: \.command) { example in
                exampleRow(example.command, meaning: example.meaning)
            }
        } header: {
            Text("Terminal")
        } footer: {
            Text(
                "Search what you saw and read your activity from any terminal. Agents that run "
                    + "commands, like Claude Code, can use it too."
            )
            .erstStyle(Typography.caption)
            .foregroundStyle(Color.erstSecondary)
        }
    }

    private var status: String {
        switch model.commandLine {
        case .installed: "Ready in any terminal, at \(model.commandLinePath)"
        case .notInstalled: "Not installed. A terminal will not find it yet."
        case .otherCopy: "Points to another copy of Erst"
        }
    }

    private var actionTitle: String {
        switch model.commandLine {
        case .installed: "Remove"
        case .notInstalled: "Install"
        case .otherCopy: "Update"
        }
    }

    private func exampleRow(_ command: String, meaning: String) -> some View {
        let copied = model.copiedCommand == command
        return HStack(spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(command)
                    .erstStyle(Typography.bodyMedium)
                    .foregroundStyle(Color.erstText)
                    .textSelection(.enabled)
                Text(meaning)
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstSecondary)
            }
            Spacer(minLength: Spacing.small)
            Button {
                model.copyCommand(command)
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(Typography.caption.font)
                    .foregroundStyle(copied ? Color.erstButter : Color.erstSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help(copied ? "Copied" : "Copy command")
            .accessibilityLabel(copied ? "Copied" : "Copy \(command)")
        }
    }
}
