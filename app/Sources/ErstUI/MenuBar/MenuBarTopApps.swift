import ErstModel
import SwiftUI

/// The three apps that took the most time today.
public struct MenuBarTopApps: View {
    private let maximumAppCount = 3
    private let apps: [AppTotal]

    public init(apps: [AppTotal]) {
        self.apps = apps
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(apps.prefix(maximumAppCount)) { total in
                HStack(spacing: Spacing.small) {
                    AppIconView(app: total.app, size: MenuBarLayout.appIconSize)
                    Text(total.app.name)
                        .erstStyle(Typography.body)
                        .foregroundStyle(Color.erstText)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.small)
                    Text(ErstFormat.duration(total.duration))
                        .erstStyle(Typography.caption)
                        .foregroundStyle(Color.erstSecondary)
                }
                .frame(height: MenuBarLayout.rowHeight)
            }
        }
        .padding(.horizontal, MenuBarLayout.contentInset)
    }
}
