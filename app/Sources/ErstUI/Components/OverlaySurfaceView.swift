import AppKit
import SwiftUI

/// Holds one overlay surface over the dim.
///
/// SwiftUI lets a click through where it has nothing to hit, such as a part that is still fading
/// in when the surface arrives. Without this view that click reaches the dim, and the dim closes
/// the overlay. Here it stops: a click inside a surface never closes it.
@MainActor
public final class OverlaySurfaceView: NSView {
    public let hosting: NSHostingView<AnyView>

    public init(_ hosting: NSHostingView<AnyView>) {
        self.hosting = hosting
        super.init(frame: .zero)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OverlaySurfaceView is created in code")
    }

    /// The surface acts on the click that activates Erst too, as the dim does.
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override public func mouseDown(with event: NSEvent) {}
    override public func rightMouseDown(with event: NSEvent) {}
    override public func otherMouseDown(with event: NSEvent) {}
}
