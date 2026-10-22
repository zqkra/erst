import AppKit
import SwiftUI

/// The Erst mark as the heat camera sees it, free on the dark surface instead of inside an icon
/// tile.
///
/// The image is the brand's thermal render (`brand/tools/build.py`, `mark-thermal.png`): coral at
/// the rim heating to a butter core, with grain, cropped to its glow. It is the brand's hero image,
/// so only the onboarding welcome shows it. Every other place uses the app icon or the flat mark.
public struct ThermalMark: View {
    private let size: CGFloat

    private static let render: NSImage? = Bundle.module
        .url(forResource: "mark-thermal", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    /// The render's glow takes about this share of each side; a flat fallback keeps the same size.
    private static let flatMarkInsetFraction: CGFloat = 0.14

    /// Creates a mark that fits a `size` square.
    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        Group {
            if let render = Self.render {
                Image(nsImage: render)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ErstMark()
                    .fill(Color.erstButter)
                    .padding(size * Self.flatMarkInsetFraction)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Erst")
    }
}
