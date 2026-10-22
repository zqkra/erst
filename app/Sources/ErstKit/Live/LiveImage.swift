import CoreGraphics
import Foundation

final class LiveImage {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }

    static func scaled(_ image: CGImage, maximum: Int) throws -> CGImage {
        let scale = min(1, Double(maximum) / Double(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw LiveMemoryError.imageUnavailable }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw LiveMemoryError.imageUnavailable }
        return result
    }
}

enum LiveMemoryError: LocalizedError {
    case imageUnavailable
    case historyChanged

    var errorDescription: String? {
        switch self {
        case .imageUnavailable: "The screen image is no longer available."
        case .historyChanged: "The history changed while the image was loading."
        }
    }
}
