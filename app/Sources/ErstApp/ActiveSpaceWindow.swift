import AppKit
import SwiftUI

/// Applies Erst's window placement to a SwiftUI scene as soon as SwiftUI creates its window.
struct ActiveSpaceWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowAttachment() }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowAttachment: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // The collection behavior has to be in place before SwiftUI orders the window.
            WindowPlacement.joinActiveSpace(window)
            // SwiftUI sizes and orders the window after attaching its content, so the final
            // placement waits one main-thread turn.
            Task { @MainActor in WindowPlacement.show(window) }
        }
    }
}

extension View {
    /// Keeps a SwiftUI scene's window where the user is: current Space, centered, in front.
    func placesWindowOnActiveSpace() -> some View { background(ActiveSpaceWindow()) }
}
