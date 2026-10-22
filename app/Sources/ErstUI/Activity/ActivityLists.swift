import ErstModel
import SwiftUI

/// One row in the apps or websites column.
public enum ActivityListRowData: Identifiable {
    case app(AppTotal)
    case site(SiteTotal)

    public var id: String {
        switch self {
        case .app(let total): "app-\(total.id)"
        case .site(let total): "site-\(total.id)"
        }
    }

    var name: String {
        switch self {
        case .app(let total): total.app.name
        case .site(let total): total.host
        }
    }

    var duration: TimeInterval {
        switch self {
        case .app(let total): total.duration
        case .site(let total): total.duration
        }
    }
}

/// A short list with proportional bars.
public struct ActivityList: View {
    private let rowHeightPoints: CGFloat = 30
    private let iconSizePoints: CGFloat = 18
    private let barHeightPoints: CGFloat = 3
    private let minimumBarWidthPoints: CGFloat = 2
    private let minimumScaleSeconds: TimeInterval = 1
    private let durationColumnWidthPoints: CGFloat = 64
    private let title: String
    private let rows: [ActivityListRowData]
    private let color: Color

    public init(title: String, rows: [ActivityListRowData], color: Color) {
        self.title = title
        self.rows = rows
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(title)
                .erstStyle(Typography.headline)
                .foregroundStyle(Color.erstText)
            VStack(spacing: Spacing.small) {
                if rows.isEmpty {
                    Text("Nothing recorded")
                        .erstStyle(Typography.caption)
                        .foregroundStyle(Color.erstSecondary)
                        .frame(height: rowHeightPoints, alignment: .leading)
                } else {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowView(_ row: ActivityListRowData) -> some View {
        let maxDuration = max(minimumScaleSeconds, rows.map(\.duration).max() ?? 0)
        return HStack(spacing: Spacing.medium) {
            icon(for: row)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(row.name)
                    .erstStyle(Typography.bodyMedium)
                    .foregroundStyle(Color.erstText)
                    .lineLimit(1)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.erstSurface)
                        Capsule()
                            .fill(color)
                            .frame(
                                width: max(
                                    minimumBarWidthPoints,
                                    proxy.size.width * CGFloat(row.duration / maxDuration)))
                    }
                }
                .frame(height: barHeightPoints)
            }
            Spacer(minLength: Spacing.small)
            Text(ErstFormat.duration(row.duration))
                .erstStyle(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Color.erstSecondary)
                .frame(width: durationColumnWidthPoints, alignment: .trailing)
        }
        .frame(height: rowHeightPoints)
    }

    @ViewBuilder
    private func icon(for row: ActivityListRowData) -> some View {
        switch row {
        case .app(let total):
            AppIconView(app: total.app, size: iconSizePoints)
        case .site:
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(Color.erstSurface)
                .frame(width: iconSizePoints, height: iconSizePoints)
                .overlay {
                    Image(systemName: "globe")
                        .font(Typography.tiny.font)
                        .foregroundStyle(Color.erstSecondary)
                }
        }
    }
}
