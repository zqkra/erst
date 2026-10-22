import AppKit
import SwiftUI

/// Gives the hosting window the dark appearance, so the system material behind Erst's light text
/// is dark too.
///
/// `.preferredColorScheme(.dark)` only changes SwiftUI's environment. A menu bar window or a
/// settings window keeps drawing its glass and material in the system appearance, and on a light
/// desktop that leaves light text on a light background.
private struct DarkWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        AppearanceView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class AppearanceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.appearance = NSAppearance(named: .darkAqua)
        }

        /// The view only sets the appearance; clicks belong to the content above it.
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

extension View {
    /// Draws the view, and the window that hosts it, in the dark appearance.
    public func darkWindowAppearance() -> some View {
        preferredColorScheme(.dark)
            .background(DarkWindowAppearance())
    }
}
