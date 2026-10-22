import ErstModel
import SwiftUI

/// A fitted frame with highlighter marks on the matched lines.
struct SearchThumbnail: View {
    let hit: SearchHit
    let image: CGImage?

    private let thumbnailAspectRatio: CGFloat = 1.6

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.erstSurface
                if let image {
                    let size = fittedSize(of: image, in: proxy.size)
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .overlay {
                            TextMatchMarks(boxes: hit.matchedLines.map(\.box))
                        }
                }
            }
        }
        .aspectRatio(thumbnailAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
        // An inner hairline keeps a dark capture from melting into the dark panel.
        .overlay {
            RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                .strokeBorder(Color.erstHairline, lineWidth: ControlMetrics.hairlinePoints)
        }
    }

    private func fittedSize(of image: CGImage, in available: CGSize) -> CGSize {
        let scale = min(available.width / CGFloat(image.width), available.height / CGFloat(image.height))
        return CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    }
}
