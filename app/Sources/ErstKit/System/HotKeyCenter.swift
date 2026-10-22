import Carbon
import Foundation
import os

private let hotKeyLog = Logger(subsystem: "app.erst.Erst", category: "HotKeyCenter")
private let hotKeySignature = OSType(0x45525354)  // "ERST"

private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    // Carbon delivers application hot keys on the main event loop.
    MainActor.assumeIsolated {
        center.handlePress(identifier: hotKeyID.id)
    }
    return noErr
}

/// Registers global shortcuts through Carbon, which needs no Accessibility permission.
@MainActor
public final class HotKeyCenter {
    private struct Registration {
        let reference: EventHotKeyRef
        let identifier: UInt32
        let handler: @MainActor @Sendable () -> Void
    }

    private var registrations: [String: Registration] = [:]
    private var nextIdentifier: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    /// Installs the Carbon event handler. Must run on the main actor.
    public init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            hotKeyLog.error("Installing hot key event handler failed with \(status, privacy: .public)")
            eventHandler = nil
        }
    }

    isolated deinit {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    /// Registers a shortcut under an identifier, replacing any previous one with the same id.
    @discardableResult
    public func register(
        _ shortcut: HotKeyShortcut,
        identifier: String,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> Bool {
        unregister(identifier)
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: nextIdentifier)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            hotKeyLog.error(
                "Registering \(identifier, privacy: .public) failed with \(status, privacy: .public)"
            )
            return false
        }
        registrations[identifier] = Registration(
            reference: reference,
            identifier: nextIdentifier,
            handler: handler
        )
        nextIdentifier += 1
        return true
    }

    /// Removes the shortcut registered under the identifier, if any.
    public func unregister(_ identifier: String) {
        guard let registration = registrations.removeValue(forKey: identifier) else { return }
        UnregisterEventHotKey(registration.reference)
    }

    /// Removes every registered shortcut.
    public func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations.removeAll()
    }

    fileprivate func handlePress(identifier: UInt32) {
        guard let registration = registrations.values.first(where: { $0.identifier == identifier })
        else { return }
        registration.handler()
    }
}
