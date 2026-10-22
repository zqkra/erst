import AppKit
import ErstModel
import SwiftUI

/// Excluded apps and the erase action.
public struct PrivacySettingsView: View {
    let model: SettingsModel

    public var body: some View {
        Form {
            Section {
                ForEach(model.settings.excludedApps) { app in
                    HStack(spacing: Spacing.medium) {
                        AppIconView(app: app, size: SettingsLayout.appIconSize)
                        Text(app.name)
                            .erstStyle(Typography.body)
                            .foregroundStyle(Color.erstText)
                        Spacer(minLength: Spacing.small)
                        Button {
                            model.removeExcludedApp(app)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Color.erstSecondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Stop excluding \(app.name)")
                    }
                }
                addAppMenu
            } header: {
                Text("Never record these apps")
            } footer: {
                Text("Password fields are never recorded.")
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstSecondary)
            }
            Section {
                Button("Erase the last hour", role: .destructive) {
                    model.showEraseConfirmation = true
                }
                .foregroundStyle(Color.erstCoral)
            }
        }
        .formStyle(.grouped)
    }

    private var addAppMenu: some View {
        Menu {
            ForEach(model.addableApps) { app in
                Button {
                    model.addExcludedApp(app)
                } label: {
                    Label {
                        Text(app.name)
                    } icon: {
                        if let icon = icon(for: app) {
                            Image(nsImage: icon)
                        } else {
                            Image(systemName: "app")
                        }
                    }
                }
            }
            Divider()
            Button("Choose...") {
                model.chooseApp()
            }
        } label: {
            Label("Add app", systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .fixedSize()
    }

    private func icon(for app: AppRef) -> NSImage? {
        if let runningIcon = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == app.bundleID })?.icon
        {
            return runningIcon
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
