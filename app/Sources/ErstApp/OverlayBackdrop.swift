import AppKit

/// The full-screen layer behind the overlay content.
///
/// It draws the dim the reference analysis keeps around its container and turns a click
/// outside the content into a close. The content is a subview on top, so clicks inside it
/// never reach this view.
///
/// The dim is the layer's background color, not a drawing: a full-screen bitmap of one color would
/// hold about 15 MB at 2x while the overlay is open, and a layer color holds none.
@MainActor
final class OverlayBackdrop: NSView {
    var onOutsideClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = OverlayLayout.dimColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OverlayBackdrop is created in code")
    }

    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    /// The dim closes the overlay, so it has to act on the click that activates Erst too.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onOutsideClick?()
    }
}
