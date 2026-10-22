import AppKit
import ErstModel
import ErstPreview
import ErstUI
import SwiftUI

/// Opens the real Timeline in a window and checks that it lands on the newest frame.
///
/// The track scroller resizes its document when the track loads and again when the first
/// scale applies. Only a real AppKit window runs that path, so the check hosts the screen.
@MainActor
enum TimelineOpenContract {
    private static let size = CGSize(width: 1440, height: 900)
    private static let settleSteps = 40
    private static let settleStep = Duration.milliseconds(25)

    static func verify(now: Date) async throws {
        let model = TimelineModel(service: PreviewMemoryService(now: now), now: now)
        // The overlay panel's style, with the screen inside a backdrop view, as the app hosts it.
        let window = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.utilityWindow, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        let backdrop = NSView(frame: CGRect(origin: .zero, size: size))
        window.contentView = backdrop
        let hosting = NSHostingView(rootView: TimelineScreen(model: model))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.autoresizingMask = []
        window.orderFront(nil)
        backdrop.addSubview(hosting)
        defer { window.orderOut(nil) }
        for _ in 0..<settleSteps {
            try await Task.sleep(for: settleStep)
            hosting.layoutSubtreeIfNeeded()
        }
        guard let track = model.track, let newest = track.frames.last else {
            throw SnapshotError.contract("The Timeline must load the preview track.")
        }
        guard model.selectedIndex == track.frames.count - 1 else {
            throw SnapshotError.contract(
                "The Timeline must open on the newest frame (\(newest.capturedAt)), "
                    + "not frame \(model.selectedIndex) (\(model.selectedDate)).")
        }
        try await verifyLayoutMoveKeepsSelection(in: hosting, model: model)
    }

    /// AppKit moves the clip view on its own during layouts and resizes, and on real use that
    /// once selected an older frame. Only the user's scrolling may select: the newest frame stays
    /// selected, even after the move loads older history in front of it, and the playhead goes
    /// back to it.
    private static func verifyLayoutMoveKeepsSelection(in hosting: NSView, model: TimelineModel)
        async throws
    {
        guard let scroller = trackScroller(in: hosting), let document = scroller.documentView else {
            throw SnapshotError.contract("The Timeline must host its track in a scroll view.")
        }
        let clip = scroller.contentView
        clip.scroll(to: NSPoint(x: 0, y: clip.bounds.origin.y))
        scroller.reflectScrolledClipView(clip)
        for _ in 0..<settleSteps {
            try await Task.sleep(for: settleStep)
            hosting.layoutSubtreeIfNeeded()
        }
        guard let track = model.track, let newest = track.frames.last,
            model.selectedFrame?.id == newest.id
        else {
            throw SnapshotError.contract(
                "A layout that moves the track must not select a frame, but frame "
                    + "\(model.selectedIndex) (\(model.selectedDate)) replaced the newest.")
        }
        // The newest frame's center is one frame from the document's end, which carries half a
        // viewport of padding on each side, so the playhead on it leaves at most one frame.
        guard document.frame.width - clip.bounds.maxX <= model.pointsPerFrame else {
            throw SnapshotError.contract(
                "After a layout moves the track, the playhead must return to the newest frame, "
                    + "not stay at x \(clip.bounds.origin.x) of \(document.frame.width).")
        }
    }

    /// The track's horizontal scroll view: the one whose document is wider than itself.
    private static func trackScroller(in view: NSView) -> NSScrollView? {
        if let scroller = view as? NSScrollView,
            let document = scroller.documentView, document.frame.width > scroller.bounds.width
        {
            return scroller
        }
        for child in view.subviews {
            if let found = trackScroller(in: child) { return found }
        }
        return nil
    }
}
