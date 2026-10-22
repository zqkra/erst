import ErstModel
import SwiftUI

/// Date, total, comparison, and the category legend.
public struct ActivitySummary: View {
    let model: ActivityModel

    private let swatchSizePoints: CGFloat = 10
    private let categories: [ActivityCategory] = [.building, .reading, .talking, .other]

    private var activeCategories: [ActivityCategory] {
        categories.filter { model.categoryTotal($0) > 0 }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(model.dateLine)
                .erstStyle(Typography.caption)
                .foregroundStyle(Color.erstSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.medium) {
                Text(model.totalText)
                    .erstStyle(Typography.display)
                    .foregroundStyle(Color.erstText)
                Text("on screen")
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstSecondary)
            }
            Text(model.comparisonText)
                .erstStyle(Typography.body)
                .foregroundStyle(Color.erstSecondary)
            HStack(spacing: Spacing.xLarge) {
                ForEach(activeCategories, id: \.self) { category in
                    HStack(spacing: Spacing.small) {
                        RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                            .fill(category.color)
                            .frame(width: swatchSizePoints, height: swatchSizePoints)
                        Text(category.displayName)
                            .erstStyle(Typography.caption)
                            .foregroundStyle(Color.erstText)
                        Text(ErstFormat.duration(model.categoryTotal(category)))
                            .erstStyle(Typography.caption)
                            .foregroundStyle(Color.erstSecondary)
                    }
                }
            }
            .padding(.top, Spacing.xSmall)
        }
    }
}
