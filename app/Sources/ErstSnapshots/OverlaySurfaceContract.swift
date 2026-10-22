import AppKit
import ErstUI
import SwiftUI

/// A click inside an overlay surface must never reach the dim behind it, because the dim closes
/// the overlay. SwiftUI lets a click through where nothing is hit, such as a part that is still
/// fully transparent while a surface arrives, so the check clicks on exactly that.
@MainActor
enum OverlaySurfaceContract {
    private static let windowSize = CGSize(width: 400, height: 300)
    private static let surfaceFrame = CGRect(x: 50, y: 50, width: 300, height: 200)

    static func verify() throws {
        guard clickReachesDim(wrapped: false) else {
            throw SnapshotError.contract(
                "A bare hosting view should let a click on a transparent part through to the dim.")
        }
        guard !clickReachesDim(wrapped: true) else {
            throw SnapshotError.contract("A click inside an overlay surface must not reach the dim.")
        }
    }

    private static func clickReachesDim(wrapped: Bool) -> Bool {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: windowSize), styleMask: [.borderless],
            backing: .buffered, defer: false)
        let dim = ClickRecordingView(frame: CGRect(origin: .zero, size: windowSize))
        window.contentView = dim
        // A part at the start of its arrival: laid out, but fully transparent.
        let hosting = NSHostingView(
            rootView: AnyView(Color.white.opacity(0).frame(maxWidth: .infinity, maxHeight: .infinity)))
        let surface: NSView = wrapped ? OverlaySurfaceView(hosting) : hosting
        surface.frame = surfaceFrame
        dim.addSubview(surface)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        window.layoutIfNeeded()
        dim.layoutSubtreeIfNeeded()
        let point = NSPoint(x: surfaceFrame.midX, y: surfaceFrame.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: 1)
            {
                window.sendEvent(event)
            }
        }
        return dim.clicked
    }
}

/// Stands in for the overlay's dim and records whether a click reached it.
private final class ClickRecordingView: NSView {
    private(set) var clicked = false

    override func mouseDown(with event: NSEvent) {
        clicked = true
    }
}
