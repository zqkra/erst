import ApplicationServices
import CoreFoundation
import Foundation

private func focusObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let relay = Unmanaged<FocusObserverRelay>.fromOpaque(refcon).takeUnretainedValue()
    relay.notify()
}

/// Retains the actor callback used as the Accessibility observer's refcon.
final class FocusObserverRelay: Sendable {
    let notify: @Sendable () -> Void

    init(notify: @escaping @Sendable () -> Void) {
        self.notify = notify
    }
}

/// An Accessibility observer for one process, watching focus and window title changes.
final class FocusObserver {
    private let observer: AXObserver
    private let application: AXUIElement
    private let relay: FocusObserverRelay
    private let runLoopSource: CFRunLoopSource
    private var observedWindow: AXUIElement?
    private var invalidated = false

    init?(processID: pid_t, onChange: @escaping @Sendable () -> Void) {
        var observer: AXObserver?
        let error = AXObserverCreate(processID, focusObserverCallback, &observer)
        guard error == .success, let observer else { return nil }
        let relay = FocusObserverRelay(notify: onChange)
        let application = AXUIElementCreateApplication(processID)
        let refcon = Unmanaged.passUnretained(relay).toOpaque()
        _ = AXObserverAddNotification(
            observer,
            application,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )
        _ = AXObserverAddNotification(
            observer,
            application,
            kAXFocusedUIElementChangedNotification as CFString,
            refcon
        )
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        self.observer = observer
        self.application = application
        self.relay = relay
        self.runLoopSource = source
    }

    deinit {
        invalidate()
    }

    func observeTitle(of window: AXUIElement?) {
        guard !invalidated else { return }
        if let observedWindow, let window, CFEqual(observedWindow, window) {
            return
        }
        if let observedWindow {
            _ = AXObserverRemoveNotification(
                observer,
                observedWindow,
                kAXTitleChangedNotification as CFString
            )
        }
        observedWindow = window
        guard let window else { return }
        _ = AXObserverAddNotification(
            observer,
            window,
            kAXTitleChangedNotification as CFString,
            Unmanaged.passUnretained(relay).toOpaque()
        )
    }

    func invalidate() {
        guard !invalidated else { return }
        invalidated = true
        if let observedWindow {
            _ = AXObserverRemoveNotification(
                observer,
                observedWindow,
                kAXTitleChangedNotification as CFString
            )
            self.observedWindow = nil
        }
        _ = AXObserverRemoveNotification(
            observer,
            application,
            kAXFocusedWindowChangedNotification as CFString
        )
        _ = AXObserverRemoveNotification(
            observer,
            application,
            kAXFocusedUIElementChangedNotification as CFString
        )
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
    }
}
