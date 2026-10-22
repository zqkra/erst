import AppKit

/// Where Erst's windows go: the Space the user is on, in front, over a full-screen app.
@MainActor
enum WindowPlacement {
    /// Lets a window follow the user instead of staying on the Space that was active at launch.
    /// Joining every Space instead would put the window in front of the user after they moved on.
    static func joinActiveSpace(_ window: NSWindow) {
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    }

    /// Centers a window on the screen with the pointer and brings it to the front.
    static func show(_ window: NSWindow) {
        joinActiveSpace(window)
        centerOnPointerScreen(window)
        bringToFront(window)
    }

    /// Brings a window forward without changing which Space it belongs to.
    static func bringToFront(_ window: NSWindow) {
        // Closing an overlay hides the app to hand focus back; unhide before showing again.
        NSApp.unhide(nil)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Since macOS 14 activation is cooperative and another app can refuse it. Ordering the
        // window regardless still shows it on the Space the user is looking at.
        if !NSApp.isActive { window.orderFrontRegardless() }
    }

    /// Centers a window on the screen that holds the pointer.
    static func centerOnPointerScreen(_ window: NSWindow) {
        guard let screen = screenWithPointer() else { return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(
            NSPoint(
                x: visible.midX - window.frame.width / 2,
                y: visible.midY - window.frame.height / 2))
    }

    /// The screen under the pointer, which is the one the user is looking at.
    static func screenWithPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}
