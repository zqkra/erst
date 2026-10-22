import AppKit
import ErstModel
import SwiftUI

/// Draws the timeline track: pause chips, segment chips, heat bars, hour labels.
///
/// Only the part inside the dirty rect is drawn, with Core Graphics and AppKit text,
/// so a two-day track scrolls without building one view per frame.
final class TimelineTrackView: NSView {
    var onSelectIndex: ((Int) -> Void)?
    var onDragEnded: (() -> Void)?

    private(set) var track: TimelineTrack?
    private(set) var layout: TimelineTrackLayout?
    private(set) var selectedIndex = 0
    private var viewportWidth: CGFloat = 0
    private var dragStart: NSPoint?
    private var dragStartOffset: CGFloat = 0
    private var didDrag = false
    private let clickTolerance: CGFloat = 3

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Typography.registerFonts()
    }

    func update(
        track: TimelineTrack?, layout: TimelineTrackLayout, selectedIndex: Int,
        viewportWidth: CGFloat
    ) {
        self.track = track
        self.layout = layout
        self.selectedIndex = selectedIndex
        self.viewportWidth = viewportWidth
        needsDisplay = true
    }

    func updateSelection(_ index: Int) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        setNeedsDisplay(visibleRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
            let track, let layout, !layout.isEmpty
        else { return }
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setShouldSmoothFonts(true)
        let offset = viewportWidth / 2
        let left = enclosingScrollView?.contentView.bounds.minX ?? 0
        let minX = dirtyRect.minX - offset
        let maxX = dirtyRect.maxX - offset
        drawHeat(context, track: track, layout: layout, offset: offset, minX: minX, maxX: maxX)
        drawSessionChips(context, track: track, layout: layout, offset: offset, minX: minX, maxX: maxX)
        drawSegmentChips(
            context, track: track, layout: layout, offset: offset, left: left,
            minX: minX, maxX: maxX)
        drawHourLabels(context, layout: layout, offset: offset, minX: minX, maxX: maxX)
    }

    // MARK: Heat

    private func drawHeat(
        _ context: CGContext, track: TimelineTrack, layout: TimelineTrackLayout, offset: CGFloat,
        minX: CGFloat, maxX: CGFloat
    ) {
        guard let range = layout.frameIndices(minX: minX, maxX: maxX) else { return }
        let width = max(
            TimelineMetrics.heatMinimumWidth, layout.pointsPerFrame - TimelineMetrics.heatBarGap)
        let bottom = TimelineMetrics.heatTop + TimelineMetrics.heatHeight
        for index in range {
            guard track.frames.indices.contains(index), layout.frameCenters.indices.contains(index),
                track.heatLevels.indices.contains(index)
            else { continue }
            let level = Int(track.heatLevels[index])
            let height =
                TimelineMetrics.heatBaseHeight + CGFloat(level) * TimelineMetrics.heatLevelStep
            let x = snapped(layout.frameCenters[index] + offset - width / 2)
            let rect = CGRect(x: x, y: bottom - height, width: snapped(width), height: height)
            context.setFillColor(TimelineTrackStyle.heatLevels[level].cgColor)
            context.addPath(heatPath(rect, radius: TimelineMetrics.heatCornerRadius))
            context.fillPath()
        }
    }

    /// Rounds a value to the device pixel grid so the heat bars stay crisp at 2x.
    private func snapped(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? 2
        return (value * scale).rounded() / scale
    }

    private func heatPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    // MARK: Session chips

    private func drawSessionChips(
        _ context: CGContext, track: TimelineTrack, layout: TimelineTrackLayout, offset: CGFloat,
        minX: CGFloat, maxX: CGFloat
    ) {
        let rectHeight = TimelineMetrics.chipHeight
        for index in layout.chips.indices {
            guard let x = layout.sessionChipX(forChip: index) else { continue }
            let rect = CGRect(
                x: x + offset, y: 0, width: TimelineMetrics.sessionChipWidth, height: rectHeight)
            guard rect.maxX >= minX, rect.minX <= maxX else { continue }
            let path = CGPath(
                roundedRect: rect, cornerWidth: TimelineMetrics.chipCornerRadius,
                cornerHeight: TimelineMetrics.chipCornerRadius, transform: nil)
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.setFillColor(TimelineTrackStyle.chipFill.cgColor)
            context.fill(rect)
            drawStripes(context, in: rect)
            context.restoreGState()
            drawSessionLabel(rect)
        }
    }

    private func drawStripes(_ context: CGContext, in rect: CGRect) {
        context.setStrokeColor(TimelineTrackStyle.stripe.cgColor)
        context.setLineWidth(TimelineMetrics.stripeWidth)
        let step = TimelineMetrics.stripePeriod * 2.squareRoot()
        var start = rect.minX - rect.height
        while start <= rect.maxX + rect.height {
            context.move(to: CGPoint(x: start, y: rect.minY))
            context.addLine(to: CGPoint(x: start - rect.height, y: rect.maxY))
            start += step
        }
        context.strokePath()
    }

    private func drawSessionLabel(_ rect: CGRect) {
        let attributes = TimelineTrackStyle.sessionAttributes
        let text = "Paused" as NSString
        let height = textHeight(attributes)
        text.draw(
            in: CGRect(
                x: rect.minX + TimelineMetrics.sessionChipLabelPadding,
                y: rect.minY + (rect.height - height) / 2,
                width: rect.width - TimelineMetrics.sessionChipLabelPadding * 2,
                height: height + 2),
            withAttributes: attributes)
    }

    // MARK: Segment chips

    private func drawSegmentChips(
        _ context: CGContext, track: TimelineTrack, layout: TimelineTrackLayout, offset: CGFloat,
        left: CGFloat, minX: CGFloat, maxX: CGFloat
    ) {
        let selectedSegment = track.frame(at: selectedIndex)?.segment
        for bounds in layout.chips {
            guard track.segments.indices.contains(bounds.run.lead) else { continue }
            guard bounds.maxX >= minX, bounds.minX <= maxX else { continue }
            let chip = CGRect(
                x: bounds.minX + offset, y: 0, width: bounds.maxX - bounds.minX,
                height: TimelineMetrics.chipHeight)
            guard chip.width > 0 else { continue }
            let selected = selectedSegment.map { bounds.run.segments.contains($0) } ?? false
            let radius =
                selected
                ? TimelineMetrics.chipSelectedCornerRadius : TimelineMetrics.chipCornerRadius
            context.setFillColor(
                (selected ? TimelineTrackStyle.chipSelectedFill : TimelineTrackStyle.chipFill).cgColor)
            context.addPath(
                CGPath(
                    roundedRect: chip, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
            let named = chipSegment(
                bounds.run, track: track, selectedSegment: selected ? selectedSegment : nil)
            drawChipContent(
                context, segment: named, detail: named.detail ?? "", chip: chip, selected: selected,
                left: left)
        }
    }

    /// The selected chip names exactly what is under the playhead, app and site, so it always
    /// agrees with the source above the track, even on a glance folded into the chip. Any other
    /// chip names its lead stretch.
    private func chipSegment(
        _ run: TrackRun, track: TimelineTrack, selectedSegment: Int?
    ) -> TrackSegment {
        if let selectedSegment, track.segments.indices.contains(selectedSegment) {
            return track.segments[selectedSegment]
        }
        return track.segments[run.lead]
    }

    private func drawChipContent(
        _ context: CGContext, segment: TrackSegment, detail: String, chip: CGRect, selected: Bool,
        left: CGFloat
    ) {
        let nameAttributes =
            selected ? TimelineTrackStyle.chipNameSelectedAttributes : TimelineTrackStyle.chipNameAttributes
        let detailAttributes =
            selected
            ? TimelineTrackStyle.chipDetailSelectedAttributes : TimelineTrackStyle.chipDetailAttributes
        let nameWidth = textWidth(segment.app.name, nameAttributes)
        let iconSide = TimelineMetrics.chipIconSize
        let gap = TimelineMetrics.chipContentGap
        let leading = TimelineMetrics.chipLeadingPadding
        let trailing = TimelineMetrics.chipTrailingPadding
        let contentX = max(chip.minX + leading, left + leading)
        let visibleWidth = chip.maxX - max(chip.minX, left)
        let available = max(0, chip.maxX - trailing - contentX)
        let nameNeeded = iconSide + gap + nameWidth
        let detailNeeded = nameNeeded + gap + TimelineMetrics.chipMinimumDetailWidth
        let showsName = visibleWidth >= TimelineMetrics.chipMinimumIconWidth && available >= nameNeeded
        let showsDetail = showsName && available >= detailNeeded

        let radius =
            selected
            ? TimelineMetrics.chipSelectedCornerRadius : TimelineMetrics.chipCornerRadius
        context.saveGState()
        context.addPath(
            CGPath(
                roundedRect: chip, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        guard showsName else {
            drawCenteredIcon(segment.app, in: chip)
            context.restoreGState()
            return
        }
        var x = contentX
        let right = chip.maxX - trailing
        drawIcon(
            segment.app,
            in: CGRect(x: x, y: (chip.height - iconSide) / 2, width: iconSide, height: iconSide))
        x += iconSide + gap
        drawText(
            segment.app.name, atX: x, width: nameWidth, attributes: nameAttributes,
            height: chip.height)
        x += nameWidth
        if showsDetail {
            let detailLimit = right - x - gap
            if detailLimit > 0 {
                drawText(
                    detail, atX: x + gap, width: detailLimit, attributes: detailAttributes,
                    height: chip.height)
            }
        }
        context.restoreGState()
    }

    /// A chip too narrow for its name still shows whose it is: the icon alone, centered, shrinking
    /// with the chip down to the smallest size that still reads, and left out below that.
    private func drawCenteredIcon(_ app: AppRef, in chip: CGRect) {
        let side = min(
            TimelineMetrics.chipIconSize, chip.width - TimelineMetrics.chipIconOnlyInset * 2)
        guard side >= TimelineMetrics.chipMinimumIconSide else { return }
        drawIcon(
            app, in: CGRect(x: chip.midX - side / 2, y: chip.midY - side / 2, width: side, height: side))
    }

    /// The icon keeps its proportions at any size: the corner radius scales with the side.
    private func drawIcon(_ app: AppRef, in rect: CGRect) {
        let icon = TimelineAppIcons.shared.icon(for: app, size: TimelineMetrics.chipIconSize)
        let radius =
            TimelineMetrics.chipIconCornerRadius * rect.width / TimelineMetrics.chipIconSize
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
        icon.draw(
            in: rect, from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawText(
        _ text: String, atX x: CGFloat, width: CGFloat, attributes: [NSAttributedString.Key: Any],
        height: CGFloat
    ) {
        guard width > 0 else { return }
        let lineHeight = textHeight(attributes)
        (text as NSString).draw(
            in: CGRect(x: x, y: (height - lineHeight) / 2, width: width, height: lineHeight + 2),
            withAttributes: attributes)
    }

    private func textWidth(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        (text as NSString).size(withAttributes: attributes).width
    }

    private func textHeight(_ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        guard let font = attributes[.font] as? NSFont else { return 13 }
        return ceil(font.ascender - font.descender)
    }

    // MARK: Hour labels

    private func drawHourLabels(
        _ context: CGContext, layout: TimelineTrackLayout, offset: CGFloat, minX: CGFloat,
        maxX: CGFloat
    ) {
        let attributes = TimelineTrackStyle.hourAttributes
        for label in layout.hourLabels {
            let text = label.text as NSString
            let width = text.size(withAttributes: attributes).width
            let center = label.x + offset
            guard center + width / 2 >= minX, center - width / 2 <= maxX else { continue }
            text.draw(
                at: CGPoint(x: center - width / 2, y: TimelineMetrics.hourLabelTop),
                withAttributes: attributes)
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragStartOffset = enclosingScrollView?.contentView.bounds.minX ?? 0
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let scrollView = enclosingScrollView as? TimelineScrollView else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = point.x - dragStart.x
        if abs(delta) > clickTolerance { didDrag = true }
        guard didDrag else { return }
        let clip = scrollView.contentView
        let maximum = max(0, bounds.width - clip.bounds.width)
        let target = min(max(dragStartOffset - delta, 0), maximum)
        scrollView.followUser {
            clip.scroll(to: NSPoint(x: target, y: clip.bounds.minY))
            scrollView.reflectScrolledClipView(clip)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if didDrag {
            onDragEnded?()
            return
        }
        guard let layout, !layout.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        onSelectIndex?(layout.index(atX: point.x - viewportWidth / 2))
    }
}
