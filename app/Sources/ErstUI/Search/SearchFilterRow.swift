import AppKit
import ErstModel
import SwiftUI

/// The app and time menus under the query field.
public struct SearchFilterRow: View {
    let model: SearchModel

    public var body: some View {
        GlassEffectContainer(spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                appMenu
                timeMenu
            }
        }
    }

    private var appMenu: some View {
        Menu {
            Button("Any app") {
                model.appFilter = nil
            }
            if !model.appChoices.isEmpty {
                Divider()
            }
            ForEach(model.appChoices) { app in
                Button {
                    model.appFilter = app
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
        } label: {
            FilterMenuLabel(title: model.appFilter?.name ?? "Any app")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .glassAction()
    }

    private var timeMenu: some View {
        Menu {
            ForEach(SearchTimeFilter.allCases) { filter in
                Button(filter.title) {
                    model.timeFilter = filter
                }
            }
        } label: {
            FilterMenuLabel(title: model.timeFilter.title)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .glassAction()
    }

    private func icon(for app: AppRef) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct FilterMenuLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: Spacing.small) {
            Text(title)
                .erstStyle(Typography.captionMedium)
                .foregroundStyle(Color.erstText)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(Typography.tiny.font)
                .foregroundStyle(Color.erstSecondary)
        }
        .contentShape(Capsule())
    }
}
