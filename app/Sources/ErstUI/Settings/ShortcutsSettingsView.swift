import ErstModel
import SwiftUI

/// The keyboard shortcuts. The two global ones can be changed; the rest are fixed.
public struct ShortcutsSettingsView: View {
    let shortcuts: ShortcutsModel

    public var body: some View {
        Form {
            Section {
                ForEach(GlobalShortcut.Action.allCases, id: \.self) { action in
                    ShortcutSettingsRow(title: action.title) {
                        ShortcutRecorderButton(model: shortcuts, action: action)
                    }
                }
                ShortcutSettingsRow(title: "Settings", keys: "\u{2318},")
            } header: {
                Text("Global")
            } footer: {
                footer
            }
            Section("Timeline") {
                ShortcutSettingsRow(title: "Step one moment", keys: "\u{2190} \u{2192}")
                ShortcutSettingsRow(title: "Step one minute", keys: "\u{21E7}\u{2190} \u{21E7}\u{2192}")
                ShortcutSettingsRow(title: "Close panel", keys: "Escape")
            }
            Section("Search") {
                ShortcutSettingsRow(title: "Move selection", keys: "\u{2191} \u{2193}")
                ShortcutSettingsRow(title: "Open moment", keys: "Return")
                ShortcutSettingsRow(title: "Clear or close", keys: "Escape")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.medium) {
            if let problem = shortcuts.problem {
                Text(problem.message)
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstCoral)
            } else if shortcuts.recording != nil {
                Text("Press the new keys. Escape cancels.")
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstSecondary)
            }
            Spacer(minLength: 0)
            if !shortcuts.isDefault {
                Button("Restore Defaults") { shortcuts.restoreDefaults() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

/// A global shortcut that turns into a recorder when clicked, like the shortcut fields in System
/// Settings.
struct ShortcutRecorderButton: View {
    let model: ShortcutsModel
    let action: GlobalShortcut.Action

    private var isRecording: Bool { model.recording == action }

    var body: some View {
        Button {
            isRecording ? model.cancelRecording() : model.beginRecording(action)
        } label: {
            Text(text)
                .erstStyle(Typography.body)
                .foregroundStyle(isRecording ? Color.erstButter : Color.erstText)
                .frame(minWidth: ShortcutRecorderMetrics.minimumWidth)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .shortcutCapture(model, for: action)
        .help(isRecording ? "Press the new keys, or Escape to cancel" : "Click to change")
    }

    private var text: String {
        guard isRecording else { return model.shortcuts[action].menuText }
        let held = model.heldModifiers.parts.map(\.glyph).joined()
        return held.isEmpty ? "Type Shortcut" : held
    }
}

private enum ShortcutRecorderMetrics {
    static let minimumWidth: CGFloat = 92
}

/// A label and its key combination, or a control in its place.
struct ShortcutSettingsRow<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Text(title)
                .erstStyle(Typography.body)
                .foregroundStyle(Color.erstText)
            Spacer(minLength: Spacing.small)
            trailing
        }
    }
}

extension ShortcutSettingsRow where Trailing == ShortcutKeysText {
    init(title: String, keys: String) {
        self.init(title: title) { ShortcutKeysText(keys: keys) }
    }
}

/// Fixed keys, in secondary text.
struct ShortcutKeysText: View {
    let keys: String

    var body: some View {
        Text(keys)
            .erstStyle(Typography.caption)
            .foregroundStyle(Color.erstSecondary)
    }
}
