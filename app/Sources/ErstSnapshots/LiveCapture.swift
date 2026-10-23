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

    static func run(folder: URL, now: Date) async throws {
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
        if let hit = try await service.search(SearchQuery(text: "open source"), limit: 1).first {
            try await capture(
                MomentScreen(service: service, moment: hit.moment, highlightedTerms: ["open", "source"])
                    .darkWindowAppearance(),
                name: "moment", size: momentSize, folder: folder)
        }
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
        window.center()
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
