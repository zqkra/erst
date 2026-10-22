import ErstModel
import SwiftUI

/// The two numbers the menu bar leads with.
public struct MenuBarStats: View {
    private let summary: TodaySummary?

    public init(summary: TodaySummary?) {
        self.summary = summary
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.large) {
            stat(value: ErstFormat.duration(summary?.onScreen ?? 0), label: "On screen today")
            stat(value: ErstFormat.bytes(summary?.keptBytes ?? 0), label: "Kept today")
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(value)
                .erstStyle(Typography.stat)
                .foregroundStyle(Color.erstText)
                .lineLimit(1)
            Text(label)
                .erstStyle(Typography.caption)
                .foregroundStyle(Color.erstSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
