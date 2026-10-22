import SwiftUI

/// A captured frame shown whole inside its container without distortion.
public struct AspectFitImage: View {
    private let image: CGImage

    public init(image: CGImage) {
        self.image = image
    }

    public var body: some View {
        GeometryReader { proxy in
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
