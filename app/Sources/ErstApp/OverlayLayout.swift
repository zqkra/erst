import AppKit

/// Size and dim of the floating overlay.
///
/// The reference analysis keeps two preset tables of the screen's visible frame: widths
/// 0.5, 0.65, 0.8 and heights 0.5, 0.65, 0.9. It centers the content container in the
/// visible frame and draws a light dim on the panel around it.
enum OverlayLayout {
    private static let widthFractions: [CGFloat] = [0.5, 0.65, 0.8]
    private static let heightFractions: [CGFloat] = [0.5, 0.65, 0.9]
    /// Search takes the 65% by 65% preset, capped so it stays a reading panel on large screens.
    private static let searchPresetIndex = 1
    private static let searchMaximumSize = NSSize(width: 1080, height: 720)
    /// Timeline and Moment take the 80% by 90% preset.
    private static let panelPresetIndex = 2
    /// Black at 22% keeps the desktop and the user's apps readable behind the glass.
    static let dimOpacity: CGFloat = 0.22
    static var dimColor: NSColor { NSColor.black.withAlphaComponent(dimOpacity) }

    static func contentSize(for surface: OverlaySurface, in visibleFrame: NSRect) -> NSSize {
        switch surface {
        case .search:
            let preset = presetSize(in: visibleFrame, index: searchPresetIndex)
            return NSSize(
                width: min(preset.width, searchMaximumSize.width),
                height: min(preset.height, searchMaximumSize.height))
        case .timeline, .moment:
            return presetSize(in: visibleFrame, index: panelPresetIndex)
        }
    }

    /// The content frame in the panel's coordinates: centered in the visible frame.
    static func contentFrame(for size: NSSize, in visibleFrame: NSRect, panelFrame: NSRect) -> NSRect {
        let frame = NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height)
        return frame.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
    }

    private static func presetSize(in visibleFrame: NSRect, index: Int) -> NSSize {
        NSSize(
            width: visibleFrame.width * widthFractions[index],
            height: visibleFrame.height * heightFractions[index])
    }
}
