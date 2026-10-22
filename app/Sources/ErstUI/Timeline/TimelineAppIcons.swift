import AppKit
import ErstModel
import SwiftUI

/// Real app icons for the dock and the chips, cached per bundle identifier and size.
///
/// Icons are rasterized at two pixels per point, and the high interpolation hint is
/// applied wherever they draw, so a 14 point chip icon stays crisp at 2x.
@MainActor
final class TimelineAppIcons {
    static let shared = TimelineAppIcons()

    private var icons: [String: NSImage] = [:]
    /// Installed icons rendered at a size, nil when the app is not on this Mac.
    private var installed: [String: NSImage?] = [:]
    private let pixelScale: CGFloat = 2

    /// The installed app's icon rendered once at this size, or nil when the app is not here.
    /// Asking IconServices for the full icon on every draw keeps its large renders resident.
    func installedIcon(for app: AppRef, size: CGFloat) -> NSImage? {
        let key = "\(app.bundleID)#\(Int(size.rounded()))"
        if let cached = installed[key] { return cached }
        let icon = source(for: app).map { render($0, points: size) }
        installed[key] = icon
        return icon
    }

    func icon(for app: AppRef, size: CGFloat) -> NSImage {
        let key = "\(app.bundleID)#\(Int(size.rounded()))"
        if let cached = icons[key] { return cached }
        let icon =
            source(for: app).map { render($0, points: size) } ?? monogram(for: app, points: size)
        icons[key] = icon
        return icon
    }

    /// The installed app's icon, or nil when the app is not on this Mac.
    private func source(for app: AppRef) -> NSImage? {
        guard
            let bundleURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: app.bundleID)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: bundleURL.path)
    }

    /// A letter tile for apps that are not installed here, in place of the generic document icon.
    private func monogram(for app: AppRef, points: CGFloat) -> NSImage {
        Typography.registerFonts()
        let trimmed = app.name.trimmingCharacters(in: .whitespaces)
        let letter = trimmed.first.map { String($0).uppercased() } ?? "?"
        return NSImage(size: NSSize(width: points, height: points), flipped: false) { rect in
            let radius = points * TimelineMetrics.monogramCornerFraction
            NSColor(TimelineStyle.monogramFill).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            let font =
                NSFont(name: TimelineType.semiboldFontName, size: points * 0.56)
                ?? .systemFont(ofSize: points * 0.56, weight: .semibold)
            let text = NSAttributedString(
                string: letter,
                attributes: [.font: font, .foregroundColor: NSColor(TimelineStyle.monogramText)])
            let size = text.size()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
    }

    /// Rasterizes the icon at its drawing size times the backing scale.
    private func render(_ source: NSImage, points: CGFloat) -> NSImage {
        let pixels = max(1, Int((points * pixelScale).rounded()))
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return source }
        bitmap.size = NSSize(width: points, height: points)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: points, height: points), from: .zero,
            operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else { return source }
        return NSImage(cgImage: image, size: NSSize(width: points, height: points))
    }
}

/// A real app icon at the dock's source size, clipped to the design's corner radius.
struct TimelineAppIcon: View {
    let app: AppRef
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Image(nsImage: TimelineAppIcons.shared.icon(for: app, size: size))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityLabel(app.name)
    }
}
