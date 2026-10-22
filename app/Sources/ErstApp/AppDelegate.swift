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
    @ObservationIgnored private var onboarding: OnboardingController?
    @ObservationIgnored private var hotKeys: HotKeyCenter?
    @ObservationIgnored private var retention: RetentionJob?
    @ObservationIgnored private var reminders: ReminderLoop?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var terminating = false
    @ObservationIgnored private var startupFailure: String?
    /// SIGTERM (kill, launchd, updaters) skips AppKit's quit path, so without this source the
    /// open video segment would never be finished.
    @ObservationIgnored private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        quitOnTerminationSignal()
        Typography.registerFonts()
        Task(priority: .utility) { await TextRecognizer.warmUp() }
        startupTask = Task { await start() }
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
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        hotKeys?.unregisterAll()
        overlays?.dismiss(restoringFocus: false, animated: false)
        statusTask?.cancel()
        permissionTask?.cancel()
        startupTask?.cancel()
        Task {
            await startupTask?.value
            await retention?.stop()
            await reminders?.stop()
            await environment?.service.shutdown()
            appLog.notice("Recorder stopped and open segment finished; quitting")
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
                onboarding?.showWelcome()
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
