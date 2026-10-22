import ServiceManagement
import os

private let loginLog = Logger(subsystem: "app.erst.Erst", category: "LoginItem")

@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
        } catch {
            loginLog.error("Updating launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
