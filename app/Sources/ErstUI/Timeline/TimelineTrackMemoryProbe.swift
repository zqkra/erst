import AppKit
import Darwin
import ErstModel
import SwiftUI

/// Measures the resident memory the real track scroller holds for a long history.
///
/// The probe lives beside the scroller so it can host the same views and document
/// sizing the Timeline uses. `ErstSnapshots` calls it and prints the numbers.
@MainActor
public enum TimelineTrackMemoryProbe {
    /// Resident byte counts around hosting and scrolling the track, plus its document width.
    public struct Reading: Sendable {
        /// Resident memory before the long track is hosted, after a small warm-up.
        public let beforeBytes: UInt64
        /// Resident memory after the first layout and draw of the long track.
        public let afterSetupBytes: UInt64
        /// Resident memory after scrolling to three positions and drawing each.
        public let afterScrollBytes: UInt64
        /// The width of the scroll document in points, for the contract's setup check.
        public let documentWidth: CGFloat

        /// Memory the long track added from before it was hosted through the last scroll.
        public var growthBytes: UInt64 {
            afterScrollBytes > beforeBytes ? afterScrollBytes - beforeBytes : 0
        }

        /// Memory the three scrolls added after the first draw.
        public var scrollGrowthBytes: UInt64 {
            afterScrollBytes > afterSetupBytes ? afterScrollBytes - afterSetupBytes : 0
        }
    }

    private static let warmupFrameCount = 10
    private static let settleSteps = 20
    private static let settleStep = Duration.milliseconds(25)
    private static let scrollFractions: [CGFloat] = [0.2, 0.5, 0.8]
    private static let scrollSettle = Duration.milliseconds(60)

    /// Hosts the track, draws it at three scroll positions, and returns the resident byte counts.
    public static func measure(
        track: TimelineTrack, pointsPerFrame: CGFloat, viewportSize: CGSize
    ) async -> Reading? {
        await warmUp(size: viewportSize)
        let before = residentBytes()
        guard let hosted = await host(track, pointsPerFrame: pointsPerFrame, size: viewportSize)
        else { return nil }
        defer { hosted.window.orderOut(nil) }
        let afterSetup = residentBytes()
        let width = hosted.scrollView.documentView?.bounds.width ?? 0
        await scroll(hosted, through: scrollFractions)
        let afterScroll = residentBytes()
        return Reading(
            beforeBytes: before, afterSetupBytes: afterSetup, afterScrollBytes: afterScroll,
            documentWidth: width)
    }

    private struct Hosted {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
        let scrollView: NSScrollView
    }

    private static func host(
        _ track: TimelineTrack, pointsPerFrame: CGFloat, size: CGSize
    ) async -> Hosted? {
        let hosting = NSHostingView(
            rootView: AnyView(
                TimelineTrackScroller(
                    track: track,
                    pointsPerFrame: pointsPerFrame,
                    selectedIndex: 0,
                    scrollGeneration: 0,
                    onScrollSelect: { _ in },
                    onClickSelect: { _ in },
                    onVisibleLowerChange: { _ in },
                    onZoom: { _, _ in }
                )
                .frame(width: size.width, height: size.height)
            )
        )
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        window.setFrameOrigin(.zero)
        window.makeKeyAndOrderFront(nil)
        await settle(hosting)
        guard let scrollView = firstScrollView(in: hosting) else {
            window.orderOut(nil)
            return nil
        }
        return Hosted(window: window, hosting: hosting, scrollView: scrollView)
    }

    /// Creates one small scroller first, so SwiftUI and AppKit startup cost stays out of the measure.
    private static func warmUp(size: CGSize) async {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let frames = (0..<warmupFrameCount).map { index in
            TrackFrame(
                id: Int64(index), capturedAt: base.addingTimeInterval(TimeInterval(index)),
                changeRatio: 0.1, segment: 0)
        }
        let end = base.addingTimeInterval(TimeInterval(warmupFrameCount - 1))
        let segment = TrackSegment(
            id: 0, app: AppRef(bundleID: "com.apple.Safari", name: "Safari"),
            host: "design.example.com", title: "Notes", frames: 0...(warmupFrameCount - 1),
            range: base...end, startsSession: true)
        let track = TimelineTrack(range: base...end, frames: frames, segments: [segment])
        guard
            let hosted = await host(
                track, pointsPerFrame: TimelineMetrics.pointsPerFrameRange.upperBound, size: size)
        else { return }
        await scroll(hosted, through: [0.5])
        hosted.window.orderOut(nil)
    }

    private static func scroll(_ hosted: Hosted, through fractions: [CGFloat]) async {
        let clip = hosted.scrollView.contentView
        let maximum = max(0, (hosted.scrollView.documentView?.bounds.width ?? 0) - clip.bounds.width)
        guard maximum > 0 else { return }
        for fraction in fractions {
            clip.scroll(to: NSPoint(x: maximum * fraction, y: clip.bounds.minY))
            hosted.scrollView.reflectScrolledClipView(clip)
            hosted.hosting.layoutSubtreeIfNeeded()
            hosted.hosting.displayIfNeeded()
            try? await Task.sleep(for: scrollSettle)
            hosted.hosting.displayIfNeeded()
        }
    }

    private static func settle(_ hosting: NSView) async {
        for _ in 0..<settleSteps {
            try? await Task.sleep(for: settleStep)
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
    }

    private static func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}
