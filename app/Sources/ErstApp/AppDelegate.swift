import AppKit
import Carbon
import ErstKit
import ErstModel
import ErstUI
import Observation
import SwiftUI
import UserNotifications
import os

private let appLog = Logger(subsystem: "app.erst.Erst", category: "AppLifecycle")

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var environment: AppEnvironment?
    private(set) var recorderStatus: RecorderStatus = .stopped
    private(set) var overlays: OverlayController?
    /// What Settings and the menu bar show about updates; the update controller drives it.
    let updates = SoftwareUpdateModel()
    /// Opens Settings. SwiftUI only hands this out to a view, so the menu bar icon passes it in.
    @ObservationIgnored var openSettingsAction: (() -> Void)?
    @ObservationIgnored private var updateController: UpdateController?
    @ObservationIgnored private var onboarding: OnboardingController?
    @ObservationIgnored private var hotKeys: HotKeyCenter?
    @ObservationIgnored private var retention: RetentionJob?
    @ObservationIgnored private var reminders: ReminderLoop?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var terminating = false
    @ObservationIgnored private var repliedToTermination = false
    /// How long a quit waits for the recorder to finish its open segment.
    private nonisolated static let shutdownDeadline: Duration = .seconds(10)
    @ObservationIgnored private var startupFailure: String?
    /// SIGTERM (kill, launchd, updaters) skips AppKit's quit path, so without this source the
    /// open video segment would never be finished.
    @ObservationIgnored private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let other = runningCopy() {
            appLog.notice(
                "Erst is already running at \(other.bundleURL?.path ?? "another path", privacy: .public); quitting this copy"
            )
            other.activate()
            NSApp.terminate(nil)
            return
        }
        quitOnTerminationSignal()
        Typography.registerFonts()
        Task(priority: .utility) { await TextRecognizer.warmUp() }
        startUpdates()
        startupTask = Task { await start() }
    }

    /// Another running Erst, such as one opened from the disk image while the installed one runs.
    /// Two copies would record the screen twice into one history, so the newer one steps aside.
    private func runningCopy() -> NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != current }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Dismissing the menu bar extra can deactivate the app for a moment while the row
        // that was clicked opens a surface. Close only if the app really stayed inactive.
        Task { @MainActor in
            guard !NSApp.isActive else { return }
            overlays?.dismiss(restoringFocus: false)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { await reopen() }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Routes SIGTERM through `NSApp.terminate`, which stops the recorder and finishes the
    /// segment in `applicationShouldTerminate`.
    private func quitOnTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            appLog.notice("SIGTERM received; quitting through AppKit")
            NSApp.terminate(nil)
        }
        source.resume()
        terminationSignal = source
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        appLog.notice("Quitting: stopping the recorder")
        hotKeys?.unregisterAll()
        overlays?.dismiss(restoringFocus: false, animated: false)
        statusTask?.cancel()
        permissionTask?.cancel()
        startupTask?.cancel()
        retention?.cancel()
        reminders?.cancel()
        // While AppKit waits for the reply it runs the main run loop in its modal panel mode, where
        // main actor tasks do not run. So the recorder stops off the main actor, and the reply is
        // delivered in that mode.
        let service = environment?.service
        Task.detached { [self] in
            await service?.shutdown()
            appLog.notice("Recorder stopped and open segment finished; quitting")
            deliverTerminationReply(sender, completed: true)
        }
        // A stuck step must never keep Erst open: the updater waits for it to quit, and a segment
        // left open is recovered at the next launch.
        Task.detached { [self] in
            try? await Task.sleep(for: Self.shutdownDeadline)
            deliverTerminationReply(sender, completed: false)
        }
        return .terminateLater
    }

    private nonisolated func deliverTerminationReply(_ sender: NSApplication, completed: Bool) {
        let modes =
            [CFRunLoopMode.commonModes.rawValue, RunLoop.Mode.modalPanel.rawValue as CFString] as CFArray
        let main = CFRunLoopGetMain()
        CFRunLoopPerformBlock(main, modes) {
            MainActor.assumeIsolated { self.finishTermination(sender, completed: completed) }
        }
        CFRunLoopWakeUp(main)
    }

    private func finishTermination(_ sender: NSApplication, completed: Bool) {
        guard !repliedToTermination else { return }
        repliedToTermination = true
        if !completed {
            appLog.error("Shutdown did not finish within the deadline; quitting anyway")
        }
        sender.reply(toApplicationShouldTerminate: true)
    }

    /// Opens Settings on About, where the update waits.
    func revealUpdate() {
        NSApp.unhide(nil)
        NSApp.activate()
        updates.revealRequested = true
        guard let openSettingsAction else {
            appLog.error("Settings could not open for the update: no settings action yet")
            return
        }
        openSettingsAction()
    }

    private func startUpdates() {
        let controller = UpdateController(model: updates)
        controller.revealInSettings = { [weak self] in self?.revealUpdate() }
        controller.start()
        updateController = controller
    }

    func fixPermission() {
        guard let environment else { return }
        onboarding?.showPermissions()
        Task { await environment.permissions.openSystemSettings(for: .screenRecording) }
    }

    /// Opening Erst again from Finder shows onboarding while a permission is missing and
    /// Search once everything is granted.
    private func reopen() async {
        if let startupTask { await startupTask.value }
        guard let environment else { return }
        let state = await environment.permissions.state()
        // Closing an overlay hides the app; opening Erst again from Finder has to unhide it.
        NSApp.unhide(nil)
        if state.screenRecording && state.accessibility {
            overlays?.showTimeline()
        } else {
            onboarding?.showPermissions()
        }
    }

    private func start() async {
        do {
            let environment = try await AppEnvironment.open()
            self.environment = environment
            appLog.notice("Engine opened at \(environment.service.dataDirectory.path, privacy: .public)")
            guard !Task.isCancelled else { return }
            overlays = OverlayController(service: environment.service)
            onboarding = OnboardingController(environment: environment)
            // Onboarding teaches the shortcuts by watching the user open the real surfaces.
            overlays?.onShow = { [weak self] surface in self?.onboarding?.noteShown(surface) }
            overlays?.onDismiss = { [weak self] in self?.onboarding?.noteOverlayDismissed() }
            configureHotKeys()
            configureNotifications()
            // Agents connected before this copy of Erst keep its current skill.
            Task { await environment.agents.refreshSkills() }
            retention = RetentionJob(service: environment.service)
            reminders = ReminderLoop(service: environment.service, scheduler: environment.reminders)
            observeStatus(environment)
            observePermissions(environment)
            let state = await environment.permissions.state()
            onboarding?.update(state)
            if !UserDefaults.standard.bool(forKey: OnboardingController.completedKey) {
                onboarding?.resume()
            } else if !state.screenRecording {
                onboarding?.showPermissions()
            } else {
                try await environment.service.startIfEnabled()
            }
            if !state.screenRecording {
                recorderStatus = .needsPermission
                appLog.notice("Screen Recording permission missing; onboarding shown")
            }
        } catch {
            guard !Task.isCancelled else { return }
            appLog.error("Opening Erst failed: \(error.localizedDescription, privacy: .public)")
            startupFailure = error.localizedDescription
            // AppKit termination must run outside the startup task that shutdown awaits.
            perform(#selector(showStartupFailure), with: nil, afterDelay: 0)
        }
    }

    @objc private func showStartupFailure() {
        guard let message = startupFailure else { return }
        startupFailure = nil
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Erst could not open its memory"
        alert.informativeText = message
        alert.addButton(withTitle: "Quit")
        NSApp.activate()
        alert.runModal()
        NSApp.terminate(nil)
    }

    private func configureHotKeys() {
        let hotKeys = HotKeyCenter()
        // The timeline is the way in; search opens from it, or directly with Shift.
        hotKeys.register(HotKeyShortcut(keyCode: 49, modifiers: UInt32(optionKey)), identifier: "timeline") {
            [weak self] in
            self?.overlays?.toggleTimeline()
        }
        hotKeys.register(
            HotKeyShortcut(keyCode: 49, modifiers: UInt32(optionKey | shiftKey)), identifier: "search"
        ) { [weak self] in
            self?.overlays?.toggleSearch()
        }
        self.hotKeys = hotKeys
    }

    private func configureNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    private func observeStatus(_ environment: AppEnvironment) {
        statusTask = Task { [weak self] in
            for await status in environment.service.status {
                guard !Task.isCancelled, let self else { return }
                recorderStatus = status
                if status == .needsPermission { onboarding?.showPermissions() }
            }
        }
    }

    private func observePermissions(_ environment: AppEnvironment) {
        permissionTask = Task { [weak self] in
            let updates = await environment.permissions.updates()
            for await state in updates {
                guard !Task.isCancelled, let self else { return }
                onboarding?.update(state)
                if !state.screenRecording {
                    onboarding?.showPermissions()
                    try? await environment.service.startIfEnabled()
                } else if UserDefaults.standard.bool(forKey: OnboardingController.completedKey),
                    onboarding?.awaitingContinue == false
                {
                    do { try await environment.service.startIfEnabled() } catch {
                        appLog.error(
                            "Starting recording failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        if identifier.hasPrefix(UpdateController.notificationPrefix) {
            await revealUpdate()
            return
        }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let id = Int64(identifier.split(separator: ".").last ?? ""), id > 0
        else { return }
        await openReminderMoment(id)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions { [.banner, .sound] }

    private func openReminderMoment(_ id: Int64) async {
        guard let environment else { return }
        do { overlays?.showMoment(try await environment.service.moment(id: id).moment) } catch {
            appLog.error("Opening reminder moment failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
