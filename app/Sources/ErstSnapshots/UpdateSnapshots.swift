import ErstModel
import ErstPreview
import ErstUI
import Foundation

/// Settings, About in each update state, and the menu bar while an update waits.
enum UpdateSnapshots {
    private static let sampleSize: Int64 = 9_800_000
    private static let sampleReceived: Int64 = 4_200_000
    private static let releasedDaysAgo = 2
    private static let checkedMinutesAgo = 12

    @MainActor
    static func capture(
        runner: SnapshotRenderer, service: PreviewMemoryService, agents: PreviewAgentClientService, now: Date
    ) async throws {
        let offer = SoftwareUpdateOffer(
            version: "0.1.1",
            notes: [
                "Search finds a phrase split across two lines.",
                "The timeline always opens on the newest moment.",
                "Agents in the terminal respect the history limit you set.",
            ],
            size: sampleSize,
            releasedAt: Calendar.current.date(byAdding: .day, value: -releasedDaysAgo, to: now)
        )
        let checked = now.addingTimeInterval(-TimeInterval(checkedMinutesAgo * 60))
        let states: [(String, SoftwareUpdatePhase)] = [
            ("up-to-date", .upToDate(lastChecked: checked)),
            ("available", .available(offer)),
            ("downloading", .downloading(offer, received: sampleReceived, expected: sampleSize)),
        ]
        for (name, phase) in states {
            try await runner.capture(
                SettingsScreen(
                    service: service, agents: agents, updates: SoftwareUpdateModel(phase: phase),
                    initialSection: .about),
                name: "settings-about-update-\(name)", width: 1000, height: 700
            )
        }
        try await runner.capture(
            MenuBarContent(service: service, updates: SoftwareUpdateModel(phase: .available(offer))),
            name: "menubar-update", width: 320
        )
    }
}
