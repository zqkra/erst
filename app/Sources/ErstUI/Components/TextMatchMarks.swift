import SwiftUI

/// Highlighter marks over matched text on a captured frame: soft rounded butter fills on the line
/// boxes, a little larger than the text, with no outline.
struct TextMatchMarks: View {
    /// Line boxes normalized to the frame, origin top-left.
    let boxes: [CGRect]

    /// The mark reaches past the text by this share of the line's height, and rounds by this share.
    private let outsetFraction: CGFloat = 0.2
    private let cornerFraction: CGFloat = 0.3
    private let minimumOutsetPoints: CGFloat = 1
    private let maximumCornerPoints: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(boxes.enumerated()), id: \.offset) { _, box in
                let rect = mark(for: box, in: proxy.size)
                RoundedRectangle(
                    cornerRadius: min(maximumCornerPoints, rect.height * cornerFraction),
                    style: .continuous
                )
                .fill(Color.erstMatchMark)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private func mark(for box: CGRect, in size: CGSize) -> CGRect {
        let rect = CGRect(
            x: box.minX * size.width, y: box.minY * size.height,
            width: box.width * size.width, height: box.height * size.height)
        let outset = max(minimumOutsetPoints, rect.height * outsetFraction)
        return rect.insetBy(dx: -outset, dy: -outset)
    }
}
