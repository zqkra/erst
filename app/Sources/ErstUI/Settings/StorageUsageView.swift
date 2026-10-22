import ErstModel
import SwiftUI

/// The usage number, bar, and legend.
public struct StorageUsageView: View {
    let report: StorageReport?
    let limit: Int?

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(usageText)
                .erstStyle(Typography.panelTitle)
                .foregroundStyle(Color.erstText)
            Text("About \(ErstFormat.bytes(report?.averagePerDayBytes ?? 0)) a day")
                .erstStyle(Typography.caption)
                .foregroundStyle(Color.erstSecondary)
            StorageBar(report: report)
                .padding(.top, Spacing.xSmall)
            StorageLegend(report: report)
        }
        .padding(.vertical, Spacing.small)
    }

    private var usageText: String {
        let used = ErstFormat.bytes(report?.usedBytes ?? 0)
        guard let limit else { return "\(used) used" }
        return "\(used) of \(limit) GB"
    }
}
