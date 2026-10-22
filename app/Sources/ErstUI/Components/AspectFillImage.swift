import SwiftUI

/// A captured frame that fills its container without distortion, cropping the overflow.
public struct AspectFillImage: View {
    private let image: CGImage

    public init(image: CGImage) {
        self.image = image
    }

    public var body: some View {
        GeometryReader { proxy in
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }
}
