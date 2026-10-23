import AppKit
import ErstUI
import SwiftUI
import os

private let menuLog = Logger(subsystem: "app.erst.Erst", category: "MenuBar")

struct AppMenu: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    let environment: AppEnvironment
    let delegate: AppDelegate

    var body: some View {
        MenuBarContent(
            service: environment.service,
            onSearch: { closeThen { delegate.overlays?.showSearch() } },
            onOpenTimeline: { closeThen { delegate.overlays?.showTimeline() } },
            onOpenActivity: {
                closeThen {
                    NSApp.activate()
                    openWindow(id: "activity")
                }
            },
            onPause: {
                closeThen {
                    Task { await environment.service.pause(until: Date().addingTimeInterval(3600)) }
                }
            },
            onResume: {
                closeThen { Task { await environment.service.setRecording(true) } }
            },
            onOpenSettings: {
                closeThen {
                    NSApp.activate()
                    openSettings()
                }
            },
            updates: delegate.updates,
            shortcuts: delegate.shortcuts,
            onUpdate: {
                closeThen {
                    NSApp.activate()
                    delegate.updates.revealRequested = true
                    openSettings()
                }
            },
            onFixPermission: { closeThen { delegate.fixPermission() } },
            onQuit: { closeThen { NSApp.terminate(nil) } }
        )
        .onAppear { menuLog.debug("Menu bar content opened") }
    }

    /// A window-style menu bar extra stays open after a row runs its action, so every row
    /// dismisses the extra first. Verified on macOS 26: the scene's dismiss action closes the
    /// MenuBarExtra window at once.
    private func closeThen(_ action: @escaping @MainActor () -> Void) {
        dismiss()
        action()
    }
}
