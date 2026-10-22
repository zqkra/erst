import AppKit
import SwiftUI

/// The real app icon in an app bundle, and the Erst mark elsewhere.
public struct AppBundleIcon: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * ControlMetrics.iconCornerFraction, style: .continuous)
                    .fill(Color.erstGround)
                    .overlay {
                        ErstMark()
                            .fill(Color.erstButter)
                            .frame(
                                width: size * ControlMetrics.markSizeFraction,
                                height: size * ControlMetrics.markSizeFraction)
                    }
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: size * ControlMetrics.iconCornerFraction, style: .continuous
                        )
                        .strokeBorder(Color.erstHairline, lineWidth: ControlMetrics.hairlinePoints)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(cornerRadius: size * ControlMetrics.iconCornerFraction, style: .continuous))
    }

    private var icon: NSImage? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return NSImage(contentsOf: url)
        }
        return NSApp.applicationIconImage
    }
}
