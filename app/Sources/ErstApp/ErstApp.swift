import ErstUI
import SwiftUI

@main
struct ErstApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { Typography.registerFonts() }

    var body: some Scene {
        MenuBarExtra {
            if let environment = delegate.environment {
                AppMenu(environment: environment, delegate: delegate)
            }
        } label: {
            MenuBarIcon(status: delegate.recorderStatus) { openSettings in
                delegate.openSettingsAction = { openSettings() }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Activity", id: "activity") {
            if let environment = delegate.environment {
                ActivityScreen(service: environment.service, period: .day)
                    .darkWindowAppearance()
                    .placesWindowOnActiveSpace()
            }
        }
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            if let environment = delegate.environment {
                SettingsScreen(
                    service: environment.service, agents: environment.agents, updates: delegate.updates,
                    shortcuts: delegate.shortcuts
                )
                .darkWindowAppearance()
                .placesWindowOnActiveSpace()
            }
        }
        .defaultSize(width: 900, height: 600)
    }
}
