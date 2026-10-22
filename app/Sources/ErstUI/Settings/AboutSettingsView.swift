import SwiftUI

/// Version, updates, description, and copyright.
public struct AboutSettingsView: View {
    let model: SettingsModel
    let updates: SoftwareUpdateModel

    public var body: some View {
        Form {
            Section {
                HStack(spacing: Spacing.large) {
                    AppBundleIcon(size: SettingsLayout.aboutIconSize)
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text("Erst")
                            .erstStyle(Typography.title)
                            .foregroundStyle(Color.erstText)
                        Text("Version \(version)")
                            .erstStyle(Typography.caption)
                            .foregroundStyle(Color.erstSecondary)
                    }
                }
                .padding(.vertical, Spacing.small)
            }
            UpdatesSection(updates: updates)
            Section {
                Text(
                    "A local memory of your screen."
                )
                .erstStyle(Typography.body)
                .foregroundStyle(Color.erstSecondary)
                .padding(.vertical, Spacing.xSmall)
            }
            Section {
                Text("Copyright 2026 Erst")
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstSecondary)
                    .padding(.vertical, Spacing.xSmall)
            }
        }
        .formStyle(.grouped)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
