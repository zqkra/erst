import AppKit
import ErstModel
import ErstPreview
import ErstUI
import Foundation
import SwiftUI

/// Shows screens in real titled windows on the display and saves what the window server draws.
///
/// Snapshots render offscreen with solid fallbacks, so they cannot show Liquid Glass, sidebar
/// materials, or the titlebar. Run `swift run ErstSnapshots --live` to see those. The windows
/// come forward without taking focus, draw as the key window, and close after the capture.
@MainActor
enum LiveCapture {
    private static let settleSeconds = 1.5
    private static let settingsSize = CGSize(width: 900, height: 600)
    private static let momentSize = CGSize(width: 1300, height: 820)
    private static let timelineSize = CGSize(width: 1300, height: 820)
    /// Where the captures draw: a 2x virtual display when one can be made, else the main screen.
    private static var screen: NSScreen?

    static func run(folder: URL, now: Date) async throws {
        screen = retinaScreen()
        let service = PreviewMemoryService(now: now)
        let agents = PreviewAgentClientService()
        for section in [SettingsSection.general, .agents] {
            try await capture(
                SettingsScreen(service: service, agents: agents, initialSection: section)
                    .darkWindowAppearance(),
                name: "settings-\(section.rawValue)", size: settingsSize, folder: folder)
        }
        let timeline = TimelineModel(service: service, now: now)
        await timeline.load()
        timeline.applyInitialScale(trackWidth: TimelineMetrics.trackWidth(surfaceWidth: timelineSize.width))
        try await capture(
            TimelineScreen(model: timeline).darkWindowAppearance(),
            name: "timeline", size: timelineSize, folder: folder)
        try await capturePanels(service: service, now: now, folder: folder)
        if let hit = try await service.search(SearchQuery(text: "open source"), limit: 1).first {
            try await capture(
                MomentScreen(service: service, moment: hit.moment, highlightedTerms: ["open", "source"])
                    .darkWindowAppearance(),
                name: "moment", size: momentSize, folder: folder)
        }
    }

    /// The overlay panels as the app shows them: borderless Liquid Glass over the dark ground, with
    /// no window around them. Each capture is the 1440 by 900 stage with the panel in its center.
    private static func capturePanels(service: PreviewMemoryService, now: Date, folder: URL) async throws {
        let panel = SnapshotStageMetrics.largePanelSize
        let timeline = TimelineModel(service: service, now: now)
        await timeline.load()
        // A dark screen, as most of the day is, so the glass dock reads as it does over code.
        if let editing = Calendar.current.date(bySettingHour: 17, minute: 8, second: 36, of: now) {
            timeline.jump(to: editing)
        }
        timeline.applyInitialScale(trackWidth: TimelineMetrics.trackWidth(surfaceWidth: panel.width))
        try await captureOnStage(
            TimelineScreen(model: timeline), name: "panel-timeline", panelSize: panel, folder: folder)
        let search = SearchModel(service: service, query: "open source")
        try await captureOnStage(
            SearchScreen(model: search), name: "panel-search",
            panelSize: SnapshotStageMetrics.searchPanelSize,
            folder: folder, isReady: { search.hasSearched })
    }

    /// The timeline going back through the day from 17:08 in three minute steps, for the website:
    /// scrolling down its page goes back through these frames, as scrolling the timeline does.
    static func runDay(folder: URL, now: Date) async throws {
        screen = retinaScreen()
        // The website's other screens show Thursday, 22 October 2026, so the day does too.
        let now =
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 10, day: 22, hour: 17, minute: 42, second: 8)) ?? now
        let service = PreviewMemoryService(now: now)
        let panel = CGSize(width: 1400, height: 984)
        let stage = CGSize(width: 1560, height: 1100)
        guard let start = Calendar.current.date(bySettingHour: 17, minute: 8, second: 36, of: now) else {
            return
        }
        for step in 0..<81 {
            let timeline = TimelineModel(service: service, now: now)
            await timeline.load()
            timeline.jump(to: start.addingTimeInterval(-Double(step) * 3 * 60))
            timeline.applyInitialScale(trackWidth: TimelineMetrics.trackWidth(surfaceWidth: panel.width))
            try await captureOnStage(
                TimelineScreen(model: timeline), name: String(format: "day-%02d", step), panelSize: panel,
                stageSize: stage, folder: folder)
        }
    }

    private static func captureOnStage<V: View>(
        _ view: V, name: String, panelSize: CGSize,
        stageSize: CGSize = CGSize(
            width: SnapshotStageMetrics.stageWidthPoints, height: SnapshotStageMetrics.stageHeightPoints),
        folder: URL, isReady: (() -> Bool)? = nil
    ) async throws {
        let stage = LiveWindow(
            contentRect: CGRect(origin: .zero, size: stageSize), styleMask: [.borderless], backing: .buffered,
            defer: false)
        stage.backgroundColor = NSColor(Color.erstGround)
        stage.isReleasedWhenClosed = false
        // Above every other window, so a floating window such as a video call cannot cover the stage.
        stage.level = .screenSaver
        place(stage)
        stage.orderFrontRegardless()
        defer { stage.orderOut(nil) }
        let panel = LiveWindow(
            contentRect: CGRect(origin: .zero, size: panelSize), styleMask: [.borderless], backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentViewController = NSHostingController(
            rootView: view.environment(\.colorScheme, .dark).font(Typography.body.font).tint(Color.erstButter)
                // A Mac with a mouse shows scroll bars at all times; a trackpad hides them until scrolling.
                .scrollIndicators(.hidden))
        panel.setContentSize(panelSize)
        panel.setFrameOrigin(
            NSPoint(x: stage.frame.midX - panelSize.width / 2, y: stage.frame.midY - panelSize.height / 2))
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while let isReady, !isReady(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .seconds(settleSeconds))
        // A connected mouse keeps scroll bars on even where a screen hides them, so the panel is
        // shown as a trackpad shows it.
        hideScrollers(in: panel.contentView)
        // A field focused on arrival selects its text; someone who just typed has the caret at its end.
        if let editor = panel.firstResponder as? NSTextView {
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
        try await Task.sleep(for: .milliseconds(300))
        // screencapture measures from the top left of the main display; AppKit from its bottom left.
        let screenHeight = NSScreen.screens.first?.frame.height ?? stage.frame.maxY
        let region =
            "\(Int(stage.frame.minX)),\(Int(screenHeight - stage.frame.maxY)),"
            + "\(Int(stageSize.width)),\(Int(stageSize.height))"
        let url = folder.appending(path: "live-\(name).png")
        let screencapture = Process()
        screencapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        screencapture.arguments = ["-R\(region)", "-x", url.path]
        try screencapture.run()
        screencapture.waitUntilExit()
        print("\(url.lastPathComponent)")
    }

    private static func retinaScreen() -> NSScreen? {
        let screen = RetinaDisplay.screen
        if screen == nil { print("No 2x virtual display, so the captures keep the main screen's scale.") }
        return screen
    }

    private static func place(_ window: NSWindow) {
        guard let screen else { return window.center() }
        window.setFrameOrigin(
            NSPoint(
                x: screen.frame.midX - window.frame.width / 2, y: screen.frame.midY - window.frame.height / 2)
        )
    }

    private static func hideScrollers(in view: NSView?) {
        guard let view else { return }
        if let scroll = view as? NSScrollView {
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
        }
        view.subviews.forEach(hideScrollers)
    }

    private static func capture<V: View>(
        _ view: V, name: String, size: CGSize, folder: URL
    ) async throws {
        let window = LiveWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(size)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        place(window)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .seconds(settleSeconds))
        let url = folder.appending(path: "live-\(name).png")
        let screencapture = Process()
        screencapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        screencapture.arguments = ["-l\(window.windowNumber)", "-o", "-x", url.path]
        try screencapture.run()
        screencapture.waitUntilExit()
        print("\(url.lastPathComponent)")
    }
}

/// macOS does not let a background tool take focus, so the window reports itself as key and main
/// to draw the active colors: selection tint, switches, and traffic lights.
private final class LiveWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
