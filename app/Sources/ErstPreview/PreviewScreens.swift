import CoreGraphics
import ErstModel
import Foundation
import ImageIO

/// The app windows a preview day shows. Each is rendered from `design/preview-screens/<name>.html`
/// by its `render.mjs` into this target's `Screens` folder: an image per variant, in the order a
/// visit moves through them, with the lines of text on each.
enum PreviewScreen: String, Sendable {
    case mail, slack, github, ghostty, zed, x, youtube, docs
}

struct PreviewScreenVariant: Sendable {
    let image: URL
    let lines: [TextLine]
}

enum PreviewScreens {
    static func variants(of screen: PreviewScreen) -> [PreviewScreenVariant] {
        guard let variants = all[screen], !variants.isEmpty else {
            preconditionFailure("No rendered variants for the \(screen.rawValue) preview screen")
        }
        return variants
    }

    /// The image, downsampled so its longer side is at most `maxPixelSize`.
    static func image(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private struct Entry: Decodable {
        let image: String
        let lines: [Line]
    }

    private struct Line: Decodable {
        let text: String
        let box: [Double]
    }

    private static let all: [PreviewScreen: [PreviewScreenVariant]] = {
        guard let folder = Bundle.module.url(forResource: "Screens", withExtension: nil),
            let data = try? Data(contentsOf: folder.appending(path: "screens.json")),
            let manifest = try? JSONDecoder().decode([String: [Entry]].self, from: data)
        else { return [:] }
        var screens: [PreviewScreen: [PreviewScreenVariant]] = [:]
        for (name, entries) in manifest {
            guard let screen = PreviewScreen(rawValue: name) else { continue }
            screens[screen] = entries.map { entry in
                PreviewScreenVariant(
                    image: folder.appending(path: entry.image),
                    lines: entry.lines.map { line in
                        TextLine(
                            text: line.text,
                            box: CGRect(
                                x: line.box[0], y: line.box[1], width: line.box[2], height: line.box[3]))
                    }
                )
            }
        }
        return screens
    }()
}
