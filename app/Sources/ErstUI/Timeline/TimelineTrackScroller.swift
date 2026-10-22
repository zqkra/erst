import AppKit
import ErstModel
import SwiftUI

/// A horizontal, elastic scroll view over the Core Graphics track.
///
/// The document view is wider than the viewport by one viewport, so the first and
/// last frames can both reach the playhead. Scrolling selects the frame under the
/// playhead, and programmatic scrolls never animate.
struct TimelineTrackScroller: NSViewRepresentable {
    let track: TimelineTrack?
    let pointsPerFrame: CGFloat
    let selectedIndex: Int
    let scrollGeneration: Int
    let onScrollSelect: (Int) -> Void
    let onClickSelect: (Int) -> Void
    let onVisibleLowerChange: (Int) -> Void
    let onZoom: (CGFloat, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TimelineScrollView {
        let scrollView = TimelineScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true
        let document = TimelineTrackView(frame: .zero)
        scrollView.documentView = document
        context.coordinator.attach(scrollView: scrollView, document: document)
        return scrollView
    }

    func updateNSView(_ scrollView: TimelineScrollView, context: Context) {
        context.coordinator.update(
            track: track,
            pointsPerFrame: pointsPerFrame,
            selectedIndex: selectedIndex,
            scrollGeneration: scrollGeneration,
            callbacks: Coordinator.Callbacks(
                scrollSelect: onScrollSelect,
                clickSelect: onClickSelect,
                visibleLower: onVisibleLowerChange,
                zoom: onZoom
            ))
    }

    @MainActor
    final class Coordinator {
        struct Callbacks {
            let scrollSelect: (Int) -> Void
            let clickSelect: (Int) -> Void
            let visibleLower: (Int) -> Void
            let zoom: (CGFloat, Int) -> Void
        }

        private weak var scrollView: TimelineScrollView?
        private weak var documentView: TimelineTrackView?
        private var callbacks: Callbacks?
        private var layout: TimelineTrackLayout?
        private var track: TimelineTrack?
        private var pointsPerFrame: CGFloat = TimelineMetrics.defaultPointsPerFrame
        private var selectedIndex = 0
        private var generation = -1
        private var lastAppliedGeneration = -1
        private var viewportWidth: CGFloat = 0
        private var lastSignature: TrackSignature?
        private var lastReportedIndex = -1
        private var lastVisibleLower = -1
        private var isScrollingProgrammatically = false
        private var needsScroll = false
        private var isRealignScheduled = false
        /// How long AppKit's rubber band keeps moving the track after the user's last event.
        private static let rubberBandSeconds: TimeInterval = 0.6

        func attach(scrollView: TimelineScrollView, document: TimelineTrackView) {
            self.scrollView = scrollView
            self.documentView = document
            scrollView.onLayout = { [weak self] in self?.viewportChanged() }
            scrollView.onScrollEnded = { [weak self] in self?.snapToPlayhead() }
            scrollView.onMagnify = { [weak self] magnification in self?.magnify(by: magnification) }
            document.onSelectIndex = { [weak self] index in self?.callbacks?.clickSelect(index) }
            document.onDragEnded = { [weak self] in self?.snapToPlayhead() }
            NotificationCenter.default.addObserver(
                self, selector: #selector(boundsChanged(_:)),
                name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            NotificationCenter.default.addObserver(
                self, selector: #selector(liveScrollEnded(_:)),
                name: NSScrollView.didEndLiveScrollNotification, object: scrollView)
        }

        func update(
            track: TimelineTrack?, pointsPerFrame: CGFloat, selectedIndex: Int,
            scrollGeneration: Int, callbacks: Callbacks
        ) {
            self.callbacks = callbacks
            self.selectedIndex = selectedIndex
            self.generation = scrollGeneration
            let signature = TrackSignature(track)
            let zoomChanged = abs(pointsPerFrame - self.pointsPerFrame) > 0.001
            self.track = track
            self.pointsPerFrame = pointsPerFrame
            if signature != lastSignature || zoomChanged {
                lastSignature = signature
                rebuildLayout()
                return
            }
            documentView?.updateSelection(selectedIndex)
            if generation != lastAppliedGeneration {
                needsScroll = true
                applyPendingScroll()
            }
        }

        private func viewportChanged() {
            guard let scrollView else { return }
            let width = scrollView.contentView.bounds.width
            guard width > 0, abs(width - viewportWidth) > 0.5 else { return }
            rebuildLayout()
        }

        private func rebuildLayout() {
            guard let scrollView, let documentView else { return }
            let viewport = scrollView.contentView.bounds.width
            guard viewport > 0 else { return }
            viewportWidth = viewport
            let layout: TimelineTrackLayout
            if let track, !track.frames.isEmpty {
                layout = TimelineTrackLayout(track: track, pointsPerFrame: pointsPerFrame)
            } else {
                layout = TimelineTrackLayout.empty
            }
            self.layout = layout
            let height = max(scrollView.contentView.bounds.height, TimelineMetrics.trackHeight)
            // Resizing the document can move the clip view, at x = 0 on the first load. That is
            // not the user scrolling, so it must not select a frame; the scroll below puts the
            // playhead back on the selection.
            isScrollingProgrammatically = true
            documentView.frame = NSRect(
                x: 0, y: 0, width: layout.contentWidth + viewport, height: height)
            documentView.update(
                track: track, layout: layout, selectedIndex: selectedIndex, viewportWidth: viewport)
            isScrollingProgrammatically = false
            needsScroll = true
            applyPendingScroll()
        }

        private func applyPendingScroll() {
            guard needsScroll else { return }
            scrollToSelected()
        }

        private func scrollToSelected() {
            guard let scrollView, let layout, !layout.frameCenters.isEmpty else {
                needsScroll = false
                lastAppliedGeneration = generation
                return
            }
            let index = min(max(selectedIndex, 0), layout.frameCenters.count - 1)
            isScrollingProgrammatically = true
            let clip = scrollView.contentView
            clip.scroll(to: NSPoint(x: layout.frameCenters[index], y: clip.bounds.origin.y))
            scrollView.reflectScrolledClipView(clip)
            isScrollingProgrammatically = false
            needsScroll = false
            lastAppliedGeneration = generation
            lastReportedIndex = index
            documentView?.updateSelection(index)
            reportVisibleLower()
        }

        @objc private func boundsChanged(_ notification: Notification) {
            guard !isScrollingProgrammatically, let scrollView, let layout, !layout.isEmpty else {
                return
            }
            if scrollView.isFollowingUser {
                let index = layout.index(atX: scrollView.contentView.bounds.origin.x)
                if index != lastReportedIndex {
                    lastReportedIndex = index
                    callbacks?.scrollSelect(index)
                }
            } else if Date().timeIntervalSince(scrollView.lastUserMove) > Self.rubberBandSeconds {
                realignAfterLayout()
            }
            reportVisibleLower()
        }

        /// AppKit moved the track by itself, during a layout or a resize. Put the playhead back on
        /// the selection once that pass ends, instead of selecting whatever frame is now under it.
        private func realignAfterLayout() {
            guard !isRealignScheduled else { return }
            isRealignScheduled = true
            Task { [weak self] in
                guard let self else { return }
                self.isRealignScheduled = false
                self.needsScroll = true
                self.applyPendingScroll()
            }
        }

        @objc private func liveScrollEnded(_ notification: Notification) {
            snapToPlayhead()
        }

        private func snapToPlayhead() {
            guard let scrollView, let layout, !layout.isEmpty else { return }
            let index = layout.index(atX: scrollView.contentView.bounds.origin.x)
            guard layout.frameCenters.indices.contains(index) else { return }
            lastReportedIndex = index
            selectedIndex = index
            callbacks?.scrollSelect(index)
            isScrollingProgrammatically = true
            let clip = scrollView.contentView
            clip.scroll(to: NSPoint(x: layout.frameCenters[index], y: clip.bounds.origin.y))
            scrollView.reflectScrolledClipView(clip)
            isScrollingProgrammatically = false
            documentView?.updateSelection(index)
            reportVisibleLower()
        }

        private func magnify(by magnification: CGFloat) {
            guard let scrollView, let layout, !layout.isEmpty else { return }
            let index = layout.index(atX: scrollView.contentView.bounds.origin.x)
            callbacks?.zoom(1 + magnification, index)
        }

        private func reportVisibleLower() {
            guard let scrollView, let layout, !layout.isEmpty else { return }
            let lower = layout.index(atX: scrollView.contentView.bounds.origin.x - viewportWidth / 2)
            guard lower != lastVisibleLower else { return }
            lastVisibleLower = lower
            callbacks?.visibleLower(lower)
        }
    }
}

private struct TrackSignature: Equatable {
    let count: Int
    let firstID: Moment.ID?
    let lastID: Moment.ID?
    let segments: Int
    let start: Date
    let end: Date

    init(_ track: TimelineTrack?) {
        count = track?.frames.count ?? 0
        firstID = track?.frames.first?.id
        lastID = track?.frames.last?.id
        segments = track?.segments.count ?? 0
        start = track?.range.lowerBound ?? .distantPast
        end = track?.range.upperBound ?? .distantPast
    }
}

/// The scroll view that turns a vertical wheel into horizontal movement.
final class TimelineScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    var onScrollEnded: (() -> Void)?
    var onMagnify: ((CGFloat) -> Void)?
    private let lineScrollPoints: CGFloat = 12
    /// True while one of the user's own events moves the track: a wheel, a trackpad scroll and
    /// its momentum, or a drag. Only those select frames; AppKit moving the clip view during a
    /// layout or a resize is not the user choosing a frame.
    private(set) var isFollowingUser = false
    /// When the user last moved the track. AppKit's rubber band settles for a moment after that.
    private(set) var lastUserMove = Date.distantPast

    /// Runs `move` as the user's own movement of the track.
    func followUser(_ move: () -> Void) {
        isFollowingUser = true
        move()
        isFollowingUser = false
        lastUserMove = Date()
    }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        followUser { scrollTrack(with: event) }
    }

    private func scrollTrack(with event: NSEvent) {
        let vertical = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
        guard vertical else {
            super.scrollWheel(with: event)
            return
        }
        let clip = contentView
        let maximum = max(0, (documentView?.bounds.width ?? 0) - clip.bounds.width)
        guard maximum > 0 else { return }
        let step =
            event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY : event.scrollingDeltaY * lineScrollPoints
        let target = min(max(clip.bounds.origin.x - step, 0), maximum)
        clip.scroll(to: NSPoint(x: target, y: clip.bounds.origin.y))
        reflectScrolledClipView(clip)
        let finished =
            event.phase == .ended || event.momentumPhase == .ended
            || (event.phase.isEmpty && event.momentumPhase.isEmpty)
        if finished {
            onScrollEnded?()
        }
    }
}
