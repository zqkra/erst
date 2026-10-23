import AppKit
import ErstKit
import ErstModel
import ErstUI
import SwiftUI
import os

private let onboardingLog = Logger(subsystem: "app.erst.Erst", category: "Onboarding")

/// First launch in its own window: the welcome, the permissions, then steps that teach by doing.
/// Recording starts as soon as the permissions are granted, so the shortcuts the user tries open a
/// timeline and a search that already hold something.
@MainActor
final class OnboardingController {
    static let completedKey = "onboardingCompleted"
    /// Set once the user is past the welcome, so a relaunch in the middle picks up at the
    /// permissions instead of greeting them again.
    private static let passedWelcomeKey = "onboardingPassedWelcome"
    private static let contentSize = NSSize(
        width: OnboardingLayout.windowWidth, height: OnboardingLayout.windowHeight)
    private(set) var awaitingContinue = false
    private let environment: AppEnvironment
    private let shortcuts: ShortcutsModel
    private let window: NSWindow
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var step: OnboardingStep = .welcome
    private var state = OnboardingState(
        permissions: PermissionsState(screenRecording: false, accessibility: false))
    private var askedForScreenRecording = false

    init(environment: AppEnvironment, shortcuts: ShortcutsModel) {
        self.environment = environment
        self.shortcuts = shortcuts
        // Deferred: most launches never show onboarding, so the window gets its backing store and
        // its content only when it first appears.
        // AppKit counts the title bar on top of the content rect even when the content runs under
        // it, so ask for the content rect that makes the whole window the designed size.
        let style: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        let designed = NSRect(origin: .zero, size: Self.contentSize)
        let titleBarHeight =
            NSWindow.frameRect(forContentRect: designed, styleMask: [.titled]).height - designed.height
        window = NSWindow(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: Self.contentSize.width, height: Self.contentSize.height - titleBarHeight)),
            styleMask: style, backing: .buffered, defer: true)
        window.title = "Welcome to Erst"
        // The welcome's art reaches the top edge, under the window buttons.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Color.erstGround)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        // The controller sizes the window itself; the hosting view would add the title bar's height.
        host.sizingOptions = []
        window.contentView = host
    }

    /// Records the permissions, and redraws only while the window shows them.
    func update(_ permissions: PermissionState) {
        state.permissions = PermissionsState(
            screenRecording: permissions.screenRecording, accessibility: permissions.accessibility)
        if window.isVisible { render() }
    }

    /// Starts onboarding, or picks it up at the permissions when the user already passed the
    /// welcome: a Screen Recording grant reaches only the next launch, so Erst quits and reopens
    /// in the middle of onboarding.
    func resume() {
        show(UserDefaults.standard.bool(forKey: Self.passedWelcomeKey) ? .permissions : .welcome)
    }

    func showPermissions() {
        if window.isVisible {
            // Keep the welcome the user is reading instead of skipping it.
            if step != .welcome {
                show(.permissions)
            }
            WindowPlacement.bringToFront(window)
            return
        }
        show(.permissions)
    }

    /// The user opened a surface with its shortcut, so the step that teaches it is done.
    func noteShown(_ surface: OverlaySurface) {
        guard window.isVisible else { return }
        switch (step, surface) {
        case (.timeline, .timeline): state.hasOpenedTimeline = true
        case (.search, .search): state.hasOpenedSearch = true
        default: return
        }
        render()
    }

    /// The overlay closed: bring the step back so the user can go on.
    func noteOverlayDismissed() {
        guard window.isVisible, awaitingContinue else { return }
        WindowPlacement.bringToFront(window)
    }

    private func show(_ step: OnboardingStep) {
        awaitingContinue = true
        self.step = step
        if step != .welcome {
            UserDefaults.standard.set(true, forKey: Self.passedWelcomeKey)
        }
        render()
        guard !window.isVisible else { return }
        WindowPlacement.show(window)
        let screen = window.screen?.localizedName ?? "no screen"
        onboardingLog.notice(
            "Onboarding shown on \(screen, privacy: .public) at \(String(describing: step), privacy: .public)"
        )
    }

    private func render() {
        let needsReopen =
            step == .permissions && askedForScreenRecording && !state.permissions.screenRecording
        host.rootView = AnyView(
            VStack(spacing: 0) {
                OnboardingScreen(step: step, state: state, actions: actions, shortcuts: shortcuts)
                if needsReopen {
                    RelaunchNotice(onReopen: { [weak self] in self?.quitAndReopen() })
                }
            }
            .frame(width: Self.contentSize.width)
            .background(Color.erstGround)
            // The window's title bar is transparent; the art runs under its buttons.
            .ignoresSafeArea()
        )
        fitWindow(needsReopen: needsReopen)
    }

    private var actions: OnboardingActions {
        OnboardingActions(
            allowScreenRecording: { [weak self] in self?.request(.screenRecording) },
            allowAccessibility: { [weak self] in self?.request(.accessibility) },
            connect: { [weak self] kind in self?.connect(kind) },
            proceed: { [weak self] in self?.advance() },
            skip: { [weak self] in self?.skip() })
    }

    /// The window keeps its designed height, plus room for the reopen notice when it shows. The
    /// content runs under the transparent title bar, so the whole frame is the content's size.
    private func fitWindow(needsReopen: Bool) {
        let noticeHeight =
            needsReopen
            ? NSHostingView(rootView: RelaunchNotice(onReopen: {}).frame(width: Self.contentSize.width))
                .fittingSize.height : 0
        let target = NSSize(width: Self.contentSize.width, height: Self.contentSize.height + noticeHeight)
        guard window.frame.size != target else { return }
        window.setFrame(NSRect(origin: window.frame.origin, size: target), display: true)
        WindowPlacement.centerOnPointerScreen(window)
    }

    private func request(_ kind: PermissionKind) {
        Task {
            let granted: Bool
            switch kind {
            case .screenRecording: granted = await environment.permissions.requestScreenRecording()
            case .accessibility: granted = await environment.permissions.requestAccessibility()
            }
            if kind == .screenRecording { askedForScreenRecording = true }
            update(await environment.permissions.state())
            if !granted { await environment.permissions.openSystemSettings(for: kind) }
        }
    }

    private func advance() {
        guard state.allowsContinue(on: step) else { return }
        switch step {
        case .welcome: show(.permissions)
        case .permissions:
            Task { await environment.service.setRecording(true) }
            show(.timeline)
        case .timeline: show(.search)
        case .search: showAgents()
        case .agents: show(.ready)
        case .ready: finish()
        }
    }

    private func skip() {
        switch step {
        case .timeline: show(.search)
        case .search: showAgents()
        default: advance()
        }
    }

    private func showAgents() {
        show(.agents)
        Task {
            state.agents = await environment.agents.clients()
            if window.isVisible { render() }
        }
    }

    private func connect(_ kind: AgentClient.Kind) {
        Task {
            do {
                try await environment.agents.connect(kind)
                state.agentError = nil
            } catch {
                let name = state.agents.first { $0.id == kind }?.name ?? "the agent"
                state.agentError = "Connecting \(name) failed: \(error.localizedDescription)"
                onboardingLog.error(
                    "Connecting an agent failed: \(error.localizedDescription, privacy: .public)")
            }
            state.agents = await environment.agents.clients()
            if window.isVisible { render() }
        }
    }

    private func finish() {
        awaitingContinue = false
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window.orderOut(nil)
        host.rootView = AnyView(EmptyView())
    }

    /// macOS hands a new Screen Recording grant to the next launch of the process, not this one.
    /// Only one Erst runs at a time, so a new copy opened now would step aside for this one: a
    /// small shell waits for this process to exit, then opens Erst again.
    private func quitAndReopen() {
        let waiter = Process()
        waiter.executableURL = URL(filePath: "/bin/sh")
        waiter.arguments = [
            "-c", #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#,
            "erst-reopen", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath,
        ]
        do {
            try waiter.run()
        } catch {
            onboardingLog.error(
                "Reopening after the grant failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }
}
