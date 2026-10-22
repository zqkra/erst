import ErstKit
import Foundation

@MainActor
final class AppEnvironment {
    let service: LiveMemoryService
    let agents: AgentClientInstaller
    let permissions = Permissions()
    let reminders = ReminderScheduler()

    private init(service: LiveMemoryService, override: URL?) {
        self.service = service
        agents = AgentClientInstaller(
            helperURL: Bundle.main.bundleURL.appending(path: "Contents/Helpers/erst"),
            dataDirectory: override,
            skillURL: Bundle.main.bundleURL.appending(path: "Contents/Resources/skill/erst"))
    }

    static func open() async throws -> AppEnvironment {
        let override = ProcessInfo.processInfo.environment["ERST_DATA_DIR"]
            .flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
        let directory =
            override ?? URL.applicationSupportDirectory.appending(path: "Erst", directoryHint: .isDirectory)
        let engine = try await LiveEngine.open(at: directory)
        return AppEnvironment(
            service: LiveMemoryService(engine: engine, dataDirectory: directory), override: override)
    }
}
