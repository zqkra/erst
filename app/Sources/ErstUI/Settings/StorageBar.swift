import ErstModel
import SwiftUI

/// The composition of kept bytes as one capsule.
public struct StorageBar: View {
    private let report: StorageReport?

    public init(report: StorageReport?) {
        self.report = report
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.erstSurface)
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Capsule()
                            .fill(segment.color)
                            .frame(width: max(0, proxy.size.width * segment.fraction))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: SettingsLayout.storageBarHeight)
    }

    private var segments: [(fraction: CGFloat, color: Color)] {
        guard let report else { return [] }
        let total = max(1, report.screensBytes + report.textBytes + report.previewsBytes)
        return [
            (CGFloat(report.screensBytes) / CGFloat(total), .erstButter),
            (CGFloat(report.textBytes) / CGFloat(total), .erstStorageText),
            (CGFloat(report.previewsBytes) / CGFloat(total), .erstStoragePreviews),
        ]
    }
}

/// The legend for the storage bar.
public struct StorageLegend: View {
    private let report: StorageReport?

    public init(report: StorageReport?) {
        self.report = report
    }

    public var body: some View {
        HStack(spacing: Spacing.large) {
            item(
                "Screens",
                bytes: report?.screensBytes ?? 0,
                color: .erstButter
            )
            item(
                "Text",
                bytes: report?.textBytes ?? 0,
                color: .erstStorageText
            )
            item(
                "Previews",
                bytes: report?.previewsBytes ?? 0,
                color: .erstStoragePreviews
            )
        }
    }

    private func item(_ label: String, bytes: Int64, color: Color) -> some View {
        HStack(spacing: Spacing.small) {
            RoundedRectangle(cornerRadius: Radius.badge, style: .continuous)
                .fill(color)
                .frame(width: SettingsLayout.storageSwatchSize, height: SettingsLayout.storageSwatchSize)
            Text(label)
                .erstStyle(Typography.caption)
                .foregroundStyle(Color.erstText)
            Text(ErstFormat.bytes(bytes))
                .erstStyle(Typography.caption)
                .foregroundStyle(Color.erstSecondary)
        }
    }
}
