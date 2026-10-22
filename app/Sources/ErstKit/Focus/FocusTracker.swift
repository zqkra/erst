import AppKit
import Carbon
import CoreGraphics
import Foundation
import os

private let focusLog = Logger(subsystem: "app.erst.Erst", category: "FocusTracker")
private let idlePollSeconds = 5.0
private let refreshDebounce = Duration.milliseconds(40)
/// `kCGAnyInputEventType` is `~0` in C. The Swift importer has no case for it, so
/// `CGEventType(rawValue: UInt32.max)` lands on `tapDisabledByUserInput`, which carries the
/// same value, and resolves to any input. The fallback only satisfies the optional type.
private let anyInputEventType = CGEventType(rawValue: UInt32.max) ?? .mouseMoved
private let browserBundleIDs: Set<String> = [
    "app.zen-browser.zen",
    "com.apple.Safari",
    "com.apple.SafariTechnologyPreview",
    "com.brave.Browser",
    "com.brave.Browser.beta",
    "com.google.Chrome",
    "com.google.Chrome.beta",
    "com.google.Chrome.canary",
    "com.kagi.kagimacOS",
    "com.microsoft.edgemac",
    "com.microsoft.edgemac.Beta",
    "com.operasoftware.Opera",
    "com.vivaldi.Vivaldi",
    "company.thebrowser.Browser",
    "company.thebrowser.dia",
    "net.imput.helium",
    "org.chromium.Chromium",
    "org.mozilla.firefox",
]

/// Tracks the frontmost app, its focused window, browser URL, and idle periods.
public actor FocusTracker {
    /// Focus and idle events as they happen.
    public nonisolated let events: AsyncStream<FocusEvent>

    private let continuation: AsyncStream<FocusEvent>.Continuation
    private var idleThresholdSeconds: TimeInterval
    private var workspaceToken: NSObjectProtocol?
    private var idleTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshScheduled = false
    private var observer: FocusObserver?
    private var frontmost: FrontmostApp?
    private var current: FocusContext?
    private var lastEmitted: FocusContext?
    private var isIdle = false
    private var running = false
    private var loggedIdleReading = false

    /// Creates a tracker. Call `start()` to begin observing.
    public init(idleThreshold: TimeInterval = 120) {
        self.idleThresholdSeconds = max(1, idleThreshold)
        let (stream, continuation) = AsyncStream.makeStream(
            of: FocusEvent.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        self.events = stream
        self.continuation = continuation
    }

    isolated deinit {
        if let workspaceToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken)
        }
    }

    /// Starts app activation and idle monitoring, and emits the first context.
    public func start() async {
        guard !running else { return }
        running = true
        let center = NSWorkspace.shared.notificationCenter
        workspaceToken = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let app = Self.frontmostApplication() else { return }
                await self?.frontmostChanged(app)
            }
        }
        if let app = await Self.frontmostApplication() {
            await frontmostChanged(app)
        }
        startIdlePolling()
    }

    /// Stops observing and finishes the event stream.
    public func stop() {
        running = false
        idleTask?.cancel()
        idleTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshScheduled = false
        observer?.invalidate()
        observer = nil
        if let workspaceToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken)
            self.workspaceToken = nil
        }
        continuation.finish()
    }

    /// The latest context, or nil before the first app activation.
    public func currentContext() -> FocusContext? {
        current
    }

    func updateIdleThreshold(_ seconds: TimeInterval) {
        idleThresholdSeconds = max(1, seconds)
        pollIdle()
    }

    /// Whether a password field currently has secure input enabled.
    public nonisolated static func isSecureInputActive() -> Bool {
        IsSecureEventInputEnabled()
    }

    @MainActor
    private static func frontmostApplication() -> FrontmostApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        // A tool without a bundle, such as a command line app with a window, keeps one identity
        // across launches through its executable name, so its time adds up under one app.
        let bundleID =
            app.bundleIdentifier
            ?? app.executableURL.map { "exec:\($0.lastPathComponent)" }
            ?? "pid:\(app.processIdentifier)"
        return FrontmostApp(
            processID: app.processIdentifier,
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID
        )
    }

    private func frontmostChanged(_ app: FrontmostApp) async {
        guard running else { return }
        let changedApp = frontmost?.processID != app.processID
        frontmost = app
        if changedApp {
            observer?.invalidate()
            observer = nil
            makeObserver(for: app)
            performRefresh()
        } else {
            makeObserver(for: app)
            scheduleRefresh()
        }
    }

    private func makeObserver(for app: FrontmostApp) {
        guard observer == nil, AccessibilityReader.isTrusted() else { return }
        observer = FocusObserver(processID: app.processID) { [weak self] in
            guard let self else { return }
            Task { await self.scheduleRefresh() }
        }
        if observer == nil {
            focusLog.notice(
                "Accessibility observer for \(app.bundleID, privacy: .public) is unavailable"
            )
        }
    }

    private func scheduleRefresh() {
        guard running, !refreshScheduled else { return }
        refreshScheduled = true
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: refreshDebounce)
            guard !Task.isCancelled else { return }
            await self?.performRefresh()
        }
    }

    private func performRefresh() {
        guard running else { return }
        refreshScheduled = false
        refreshTask = nil
        guard let frontmost else { return }
        makeObserver(for: frontmost)
        let context = readContext(for: frontmost)
        current = context
        guard lastEmitted?.hasSameIdentity(as: context) != true else { return }
        lastEmitted = context
        continuation.yield(.changed(context))
    }

    private func readContext(for app: FrontmostApp) -> FocusContext {
        let observedAt = Date()
        guard AccessibilityReader.isTrusted() else {
            return FocusContext(
                bundleID: app.bundleID,
                appName: app.appName,
                processID: app.processID,
                windowTitle: nil,
                url: nil,
                at: observedAt
            )
        }
        let application = AccessibilityReader.application(processID: app.processID)
        let window = AccessibilityReader.focusedWindow(of: application)
        observer?.observeTitle(of: window)
        let title = window.flatMap { AccessibilityReader.title(of: $0) }
        var url: URL?
        if browserBundleIDs.contains(app.bundleID) {
            let root = window ?? AccessibilityReader.focusedElement(of: application)
            if let root {
                url = AccessibilityReader.browserURL(from: root)
            }
        }
        return FocusContext(
            bundleID: app.bundleID,
            appName: app.appName,
            processID: app.processID,
            windowTitle: title,
            url: url,
            at: observedAt
        )
    }

    private func startIdlePolling() {
        idleTask = Task { [weak self] in
            guard let self else { return }
            await self.pollIdle()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(idlePollSeconds))
                guard !Task.isCancelled else { return }
                await self.pollIdle()
            }
        }
    }

    private func pollIdle() {
        guard running else { return }
        let seconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInputEventType
        )
        if !loggedIdleReading {
            loggedIdleReading = true
            focusLog.notice("Idle at start: \(seconds, privacy: .public) s since any input")
        }
        if seconds >= idleThresholdSeconds {
            guard !isIdle else { return }
            isIdle = true
            continuation.yield(.idle(since: Date().addingTimeInterval(-seconds)))
        } else {
            guard isIdle else { return }
            isIdle = false
            continuation.yield(.resumed(at: Date()))
        }
    }
}
