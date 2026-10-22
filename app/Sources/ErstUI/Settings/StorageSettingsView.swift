import ErstModel
import SwiftUI

/// Disk usage, retention, and the folder Erst writes to.
public struct StorageSettingsView: View {
    let model: SettingsModel

    public var body: some View {
        Form {
            Section {
                StorageUsageView(report: model.storage, limit: model.settings.storageLimitGigabytes)
            }
            Section("History") {
                Picker("Keep full quality for", selection: model.binding(\.fullQualityDays)) {
                    ForEach(ErstSettings.fullQualityDayChoices, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                Picker("Then keep a lighter copy for", selection: model.binding(\.lighterCopyMonths)) {
                    ForEach(ErstSettings.lighterCopyMonthChoices, id: \.self) { months in
                        Text(months.map { $0 == 1 ? "1 month" : "\($0) months" } ?? "Forever").tag(months)
                    }
                }
                Picker("After that", selection: model.binding(\.afterLighterCopy)) {
                    ForEach(ErstSettings.AfterLighterCopy.allCases, id: \.self) { action in
                        Text(action.title).tag(action)
                    }
                }
            }
            Section("Storage") {
                Picker("Never use more than", selection: model.binding(\.storageLimitGigabytes)) {
                    ForEach(ErstSettings.storageLimitChoices, id: \.self) { gigabytes in
                        Text(gigabytes.map { "\($0) GB" } ?? "No limit").tag(gigabytes)
                    }
                }
            }
            Section("Data folder") {
                HStack(spacing: Spacing.medium) {
                    Text(model.dataFolder.path)
                        .erstStyle(Typography.caption)
                        .foregroundStyle(Color.erstSecondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer(minLength: Spacing.small)
                    Button("Show in Finder") {
                        model.showInFinder()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
