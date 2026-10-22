import AppKit

/// The panel under the overlay chain.
///
/// The reference analysis creates a borderless non-activating panel (style mask 0x8090:
/// utility window, non-activating panel, full size content) at level 4, transparent, with
/// no shadow, that can still become key and main so typing works once the app is active.
@MainActor
final class OverlayPanel: NSPanel {
    var onEscape: (() -> Void)?

    private static let escapeKeyCode: UInt16 = 53
    /// Level 4 is one step above floating, the level the reference analysis raises to.
    private static let overlayLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.utilityWindow, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        level = Self.overlayLevel
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        canHide = false
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // Transient plus full screen auxiliary, without joining every Space: the panel stays on
        // the Space where the user opened it and can appear over another app's full-screen window.
        collectionBehavior = [.transient, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown:
            // A non-activating panel ordered front can receive events before the app is active.
            if !NSApp.isActive { NSApp.activate() }
            if !isKeyWindow { makeKey() }
        default:
            break
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == Self.escapeKeyCode {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}
