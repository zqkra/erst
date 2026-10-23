import AppKit
import ErstModel
import ErstPreview
import ErstUI
import Foundation
import SwiftUI

@main
struct ErstSnapshots {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        Typography.registerFonts()
        // ERST_HOLD_ARRIVAL=0.3 renders every surface 30% into its arrival, to check the stagger.
        if let held = ProcessInfo.processInfo.environment["ERST_HOLD_ARRIVAL"].flatMap(Double.init) {
            Motion.heldArrival = CGFloat(held)
        }
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--installer-background"), flag + 1 < arguments.count {
            try InstallerBackground.write(to: URL(filePath: arguments[flag + 1], directoryHint: .isDirectory))
            return
        }
        if CommandLine.arguments.contains("--live") {
            try await LiveCapture.run(folder: try SnapshotPaths.createSnapshotsFolder(), now: sampleNow())
            return
        }
        try await SnapshotContracts.verify()

        let folder = try SnapshotPaths.createSnapshotsFolder()
        let now = sampleNow()
        let service = PreviewMemoryService(now: now)
        let agents = PreviewAgentClientService()
        let empty = PreviewMemoryService(now: now, includesHistory: false)
        let runner = SnapshotRenderer(folder: folder)

        for (name, status) in menuBarStates {
            try await runner.capture(
                MenuBarContent(service: PreviewMemoryService(now: now, status: status)),
                name: "menubar-\(name)", width: 320
            )
        }
        let agentClients = await agents.clients()
        for step in OnboardingStep.allCases {
            try await runner.capture(
                OnboardingScreen(step: step, state: onboardingState(for: step, agents: agentClients)),
                name: "onboarding-\(stepName(step))", width: OnboardingLayout.windowWidth,
                height: OnboardingLayout.windowHeight
            )
        }
        try await captureShortcutChanges(
            runner: runner, service: service, agents: agents, clients: agentClients)
        let midHistory = TimelineModel(service: service, now: now)
        await midHistory.load()
        if let midDate = Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: now) {
            midHistory.jump(to: midDate)
        }
        let timelineTrackWidth = TimelineMetrics.trackWidth(
            surfaceWidth: SnapshotStageMetrics.largePanelSize.width)
        midHistory.applyInitialScale(trackWidth: timelineTrackWidth)
        try await runner.captureOverlay(
            TimelineScreen(model: midHistory),
            name: "timeline-mid-history",
            panelSize: SnapshotStageMetrics.largePanelSize
        )
        let latest = TimelineModel(service: service, now: now)
        await latest.load()
        latest.applyInitialScale(trackWidth: timelineTrackWidth)
        try await runner.captureOverlay(
            TimelineScreen(model: latest),
            name: "timeline-latest",
            panelSize: SnapshotStageMetrics.largePanelSize
        )
        let hour = TimelineModel(service: service, now: now)
        await hour.load()
        if let hourDate = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: now) {
            hour.jump(to: hourDate)
        }
        hour.applyInitialScale(trackWidth: timelineTrackWidth)
        hour.setScale(.hour, trackWidth: timelineTrackWidth)
        try await runner.captureOverlay(
            TimelineScreen(model: hour),
            name: "timeline-hour",
            panelSize: SnapshotStageMetrics.largePanelSize
        )
        let month = TimelineModel(service: service, now: now)
        await month.load()
        if let monthDate = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: now) {
            month.jump(to: monthDate)
        }
        month.applyInitialScale(trackWidth: timelineTrackWidth)
        month.setScale(.month, trackWidth: timelineTrackWidth)
        try await runner.captureOverlay(
            TimelineScreen(model: month),
            name: "timeline-month",
            panelSize: SnapshotStageMetrics.largePanelSize,
            isReady: { !month.month.days.isEmpty && month.image != nil }
        )
        for progress in [0.25, 0.5, 0.75, 1.0] {
            let searching = TimelineModel(service: service, now: now)
            await searching.load()
            searching.applyInitialScale(trackWidth: timelineTrackWidth)
            try await runner.captureOverlay(
                TimelineScreen(
                    model: searching,
                    search: TimelineSearchPresentation(progress: CGFloat(progress))),
                name: "timeline-search-\(Int(progress * 100))",
                panelSize: SnapshotStageMetrics.largePanelSize
            )
        }
        try await runner.captureOverlay(
            TimelineScreen(service: empty, now: now),
            name: "timeline-empty",
            panelSize: SnapshotStageMetrics.largePanelSize
        )
        for (name, query) in searchStates {
            let model = SearchModel(service: service, query: query)
            try await runner.captureOverlay(
                SearchScreen(model: model),
                name: "search-\(name)",
                panelSize: SnapshotStageMetrics.searchPanelSize,
                isReady: { model.trimmedQuery.isEmpty ? !model.recent.isEmpty : model.hasSearched }
            )
        }
        guard let hit = try await service.search(SearchQuery(text: "open source"), limit: 1).first else {
            throw SnapshotError.noMoment
        }
        try await runner.captureOverlay(
            MomentScreen(service: service, moment: hit.moment, highlightedTerms: ["open", "source"]),
            name: "moment-search",
            panelSize: SnapshotStageMetrics.largePanelSize
        )
        let expanded = MomentModel(
            service: service, moment: hit.moment, highlightedTerms: ["open", "source"])
        expanded.toggleTextExpanded()
        try await runner.captureOverlay(
            MomentScreen(model: expanded),
            name: "moment-text-expanded",
            panelSize: SnapshotStageMetrics.largePanelSize
        )
        for period in [ActivityModel.Period.day, .week] {
            try await runner.capture(
                ActivityScreen(service: service, period: period),
                name: "activity-\(period.rawValue)", width: 1180, height: 780
            )
        }
        for section in SettingsSection.allCases {
            try await runner.capture(
                SettingsScreen(service: service, agents: agents, initialSection: section),
                name: "settings-\(section.rawValue)", width: 1000, height: 700
            )
        }
        try await runner.capture(
            SettingsScreen(
                service: service, agents: agents, initialSection: .privacy, showingEraseConfirmation: true
            ),
            name: "settings-erase-confirmation", width: 1000, height: 700
        )
        try await UpdateSnapshots.capture(runner: runner, service: service, agents: agents, now: now)
        print("Snapshots written to \(folder.path)")
        exit(0)
    }

    /// Changing a global shortcut: onboarding while it waits for keys and after it changed, and
    /// Settings while it records with keys macOS holds.
    @MainActor
    private static func captureShortcutChanges(
        runner: SnapshotRenderer, service: PreviewMemoryService, agents: PreviewAgentClientService,
        clients: [AgentClient]
    ) async throws {
        let custom = ShortcutSet(
            timeline: GlobalShortcut(keyCode: 40, modifiers: [.control, .option], key: "K"),
            search: ShortcutSet.default.search)
        let state = onboardingState(for: .timeline, agents: clients)
        for (name, model) in [
            ("changing", ShortcutsModel(recording: .timeline)), ("custom", ShortcutsModel(shortcuts: custom)),
        ] {
            try await runner.capture(
                OnboardingScreen(step: .timeline, state: state, shortcuts: model),
                name: "onboarding-timeline-\(name)", width: OnboardingLayout.windowWidth,
                height: OnboardingLayout.windowHeight)
        }
        try await runner.capture(
            SettingsScreen(
                service: service, agents: agents,
                shortcuts: ShortcutsModel(shortcuts: custom, recording: .search, problem: .usedByMacOS),
                initialSection: .shortcuts),
            name: "settings-shortcuts-recording", width: 1000, height: 700)
    }

    private static let menuBarStates: [(String, RecorderStatus)] = [
        ("recording", .recording), ("paused", .paused(until: nil)), ("permission", .needsPermission),
    ]
    private static let searchStates = [
        ("results", "open source"), ("no-results", "unfindableword"), ("empty", ""),
    ]

    private static func stepName(_ step: OnboardingStep) -> String {
        switch step {
        case .welcome: "welcome"
        case .permissions: "permissions"
        case .timeline: "timeline"
        case .search: "search"
        case .agents: "agents"
        case .ready: "ready"
        }
    }

    /// Each step in the state that shows it best: one permission still to grant, the timeline
    /// shortcut still to press, search already tried.
    private static func onboardingState(for step: OnboardingStep, agents: [AgentClient]) -> OnboardingState {
        let granted = step != .welcome && step != .permissions
        return OnboardingState(
            permissions: PermissionsState(screenRecording: step != .welcome, accessibility: granted),
            hasOpenedSearch: step == .search, agents: agents)
    }

    private static func sampleNow() -> Date {
        Calendar.current.date(bySettingHour: 17, minute: 42, second: 8, of: Date()) ?? Date()
    }
}

enum SnapshotError: Error {
    case noMoment
    case bitmap
    case png
    case contract(String)
}
