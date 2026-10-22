import AppKit
import ErstModel
import SwiftUI

/// The real app icon when it exists, and a quiet monogram when it does not.
public struct AppIconView: View {
    private let app: AppRef
    private let size: CGFloat

    public init(app: AppRef, size: CGFloat) {
        self.app = app
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = TimelineAppIcons.shared.installedIcon(for: app, size: size) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * ControlMetrics.iconCornerFraction, style: .continuous)
                    .fill(Color.erstIconPlaceholder)
                    .overlay {
                        Text(String(app.name.prefix(1)))
                            .font(Typography.chipTitle.font)
                            .foregroundStyle(Color.erstText)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(cornerRadius: size * ControlMetrics.iconCornerFraction, style: .continuous)
        )
        .accessibilityLabel(app.name)
    }
}
