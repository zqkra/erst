import SwiftUI

/// The fixed keyboard shortcuts.
public struct ShortcutsSettingsView: View {
    let model: SettingsModel

    public var body: some View {
        Form {
            Section("Global") {
                ShortcutSettingsRow(title: "Open timeline", keys: "⌥Space")
                ShortcutSettingsRow(title: "Search everything", keys: "⌥⇧Space")
                ShortcutSettingsRow(title: "Settings", keys: "⌘,")
            }
            Section("Timeline") {
                ShortcutSettingsRow(title: "Step one moment", keys: "← →")
                ShortcutSettingsRow(title: "Step one minute", keys: "⇧← ⇧→")
                ShortcutSettingsRow(title: "Close panel", keys: "Escape")
            }
            Section("Search") {
                ShortcutSettingsRow(title: "Move selection", keys: "↑ ↓")
                ShortcutSettingsRow(title: "Open moment", keys: "Return")
                ShortcutSettingsRow(title: "Clear or close", keys: "Escape")
            }
            Section {
                Text("Shortcuts are fixed in this version.")
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstSecondary)
                    .padding(.vertical, Spacing.xSmall)
            }
        }
        .formStyle(.grouped)
    }
}

/// A label and its key combination.
public struct ShortcutSettingsRow: View {
    private let title: String
    private let keys: String

    public init(title: String, keys: String) {
        self.title = title
        self.keys = keys
    }

    public var body: some View {
        HStack(spacing: Spacing.medium) {
            Text(title)
                .erstStyle(Typography.body)
                .foregroundStyle(Color.erstText)
            Spacer(minLength: Spacing.small)
            Text(keys)
                .erstStyle(Typography.caption)
                .foregroundStyle(Color.erstSecondary)
        }
    }
}
