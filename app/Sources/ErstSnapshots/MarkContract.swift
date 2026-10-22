import AppKit
import CoreGraphics
import ErstUI
import Foundation

/// Compares the code mark with the brand SVG and writes both renders for review.
@MainActor
enum MarkContract {
    private static let pixelSize = 256
    private static let tileSize = 16
    private static let maximumMeanDifference = 0.02
    private static let maximumTileDifference = 0.10
    private static let menuBarSizePoints: CGFloat = 18
    private static let menuBarScale: CGFloat = 2

    static func verify() throws {
        let code = try rasterizeMark(points: CGFloat(pixelSize), pixels: pixelSize)
        let svg = try rasterizeSVG(pixels: pixelSize)
        let mean = meanDifference(code.alpha, svg.alpha)
        let worstTile = worstTileDifference(code.alpha, svg.alpha)
        print(
            String(
                format: "mark: mean alpha difference %.2f%%, worst 16 px tile %.2f%%.",
                mean * 100, worstTile * 100))
        try require(
            mean < maximumMeanDifference,
            "The code mark must stay within 2 percent of the brand SVG on average.")
        try require(
            worstTile < maximumTileDifference,
            "No 16 by 16 tile of the code mark may differ from the brand SVG by over 10 percent.")

        let folder = try SnapshotPaths.createSnapshotsFolder()
        try write(code, name: "mark-code.png", folder: folder)
        try write(svg, name: "mark-svg.png", folder: folder)
        let menuBar = try rasterizeMark(
            points: menuBarSizePoints, pixels: Int(menuBarSizePoints * menuBarScale))
        try write(menuBar, name: "mark-menubar.png", folder: folder)
    }

    private struct Raster {
        let image: CGImage
        let alpha: [UInt8]
    }

    /// Fills the shape into a y-flipped context so the bitmap is upright like the SVG.
    private static func rasterizeMark(points: CGFloat, pixels: Int) throws -> Raster {
        let context = try bitmapContext(pixels: pixels)
        let scale = CGFloat(pixels) / points
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: points)
        context.scaleBy(x: 1, y: -1)
        context.addPath(ErstMark().path(in: CGRect(x: 0, y: 0, width: points, height: points)).cgPath)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath(using: .winding)
        return try raster(from: context, pixels: pixels)
    }

    private static func rasterizeSVG(pixels: Int) throws -> Raster {
        guard let image = NSImage(contentsOf: SnapshotPaths.mark) else {
            throw SnapshotError.contract("The brand mark SVG must load.")
        }
        let context = try bitmapContext(pixels: pixels)
        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
            from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return try raster(from: context, pixels: pixels)
    }

    private static func bitmapContext(pixels: Int) throws -> CGContext {
        guard
            let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw SnapshotError.contract("The mark needs a bitmap context.") }
        return context
    }

    private static func raster(from context: CGContext, pixels: Int) throws -> Raster {
        guard let image = context.makeImage(), let data = context.data else {
            throw SnapshotError.contract("The mark render must produce a bitmap.")
        }
        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * pixels)
        var alpha = [UInt8](repeating: 0, count: pixels * pixels)
        for row in 0..<pixels {
            for column in 0..<pixels {
                alpha[row * pixels + column] = bytes[row * context.bytesPerRow + column * 4 + 3]
            }
        }
        return Raster(image: image, alpha: alpha)
    }

    private static func meanDifference(_ first: [UInt8], _ second: [UInt8]) -> Double {
        var total = 0
        for (firstPixel, secondPixel) in zip(first, second) {
            total += abs(Int(firstPixel) - Int(secondPixel))
        }
        return Double(total) / (Double(first.count) * 255)
    }

    private static func worstTileDifference(_ first: [UInt8], _ second: [UInt8]) -> Double {
        var worst = 0.0
        for tileY in stride(from: 0, to: pixelSize, by: tileSize) {
            for tileX in stride(from: 0, to: pixelSize, by: tileSize) {
                var total = 0
                for row in tileY..<(tileY + tileSize) {
                    for column in tileX..<(tileX + tileSize) {
                        let index = row * pixelSize + column
                        total += abs(Int(first[index]) - Int(second[index]))
                    }
                }
                worst = max(worst, Double(total) / (Double(tileSize * tileSize) * 255))
            }
        }
        return worst
    }

    private static func write(_ raster: Raster, name: String, folder: URL) throws {
        guard
            let data = NSBitmapImageRep(cgImage: raster.image).representation(
                using: .png, properties: [:])
        else { throw SnapshotError.png }
        let url = folder.appending(path: name)
        try data.write(to: url)
        print("\(name): \(raster.image.width)x\(raster.image.height)")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SnapshotError.contract(message) }
    }
}
