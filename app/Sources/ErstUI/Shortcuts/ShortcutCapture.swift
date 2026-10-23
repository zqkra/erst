import AppKit
import ErstModel
import SwiftUI

extension View {
    /// Leaving the view while it records `action` cancels the recording, so the global
    /// shortcuts never stay paused.
    func shortcutCapture(_ model: ShortcutsModel, for action: GlobalShortcut.Action) -> some View {
        onDisappear {
            if model.recording == action { model.cancelRecording() }
        }
    }
}

/// Reads the keys pressed in Erst's windows while a shortcut records. Escape cancels, and so
/// does leaving the app.
@MainActor
final class ShortcutKeyReader {
    private var monitor: Any?
    private var resignObserver: (any NSObjectProtocol)?

    func start(
        onModifiers: @escaping @MainActor @Sendable (GlobalShortcut.Modifiers) -> Void,
        onKeys: @escaping @MainActor @Sendable (GlobalShortcut) -> Void,
        onCancel: @escaping @MainActor @Sendable () -> Void
    ) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let modifiers = GlobalShortcut.Modifiers(event.modifierFlags)
            switch event.type {
            case .flagsChanged:
                onModifiers(modifiers)
                return event
            case .keyDown:
                if event.keyCode == GlobalShortcut.escapeKeyCode && modifiers.isEmpty {
                    onCancel()
                } else {
                    let character = event.characters(byApplyingModifiers: []) ?? ""
                    onKeys(
                        GlobalShortcut(
                            keyCode: event.keyCode, modifiers: modifiers,
                            key: GlobalShortcut.keyName(keyCode: event.keyCode, character: character)))
                }
                // The keys belong to the recorder, not to the focused control.
                return nil
            default:
                return event
            }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onCancel() }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }
}

extension GlobalShortcut.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: GlobalShortcut.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}
