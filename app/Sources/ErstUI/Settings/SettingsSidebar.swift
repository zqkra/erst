import SwiftUI

/// The native sidebar: a source list, so macOS draws it as the floating glass pane with its own
/// selection, hover, and keyboard focus. About sits in its own group at the end.
public struct SettingsSidebar: View {
    let model: SettingsModel

    public var body: some View {
        List(
            selection: Binding(
                get: { Optional(model.section) },
                set: { model.section = $0 ?? model.section })
        ) {
            Section {
                ForEach(SettingsSection.mainSections) { section in
                    row(section)
                }
            }
            Section {
                row(.about)
            }
        }
        .listStyle(.sidebar)
        // The selection fills with the tint and turns its text white, so the tint is the quiet
        // butter wash and never full butter, which white text cannot sit on.
        .tint(Color.erstSelection)
        .toolbar(removing: .sidebarToggle)
        .navigationSplitViewColumnWidth(
            min: SettingsLayout.sidebarMinimumWidth,
            ideal: SettingsLayout.sidebarIdealWidth,
            max: SettingsLayout.sidebarMaximumWidth
        )
    }

    /// Icons stay gray and turn butter on the selected row, the one place the accent marks.
    private func row(_ section: SettingsSection) -> some View {
        Label {
            Text(section.title).erstStyle(Typography.body)
        } icon: {
            Image(systemName: section.symbol)
                .foregroundStyle(model.section == section ? Color.erstButter : Color.erstSecondary)
        }
        .tag(section)
    }
}
