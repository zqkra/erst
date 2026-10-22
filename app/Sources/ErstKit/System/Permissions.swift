import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

private let permissionsLog = Logger(subsystem: "app.erst.Erst", category: "Permissions")

/// Checks, requests, and watches the privacy permissions Erst needs.
public actor Permissions {
    private var continuation: AsyncStream<PermissionState>.Continuation?
    private var lastPublished: PermissionState?
    private var defaultTokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = []

    /// Creates a permission monitor. Call `updates()` to begin observing.
    public init() {}

    isolated deinit {
        for token in defaultTokens {
            NotificationCenter.default.removeObserver(token)
        }
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    /// Whether screen recording is currently granted, without prompting.
    public nonisolated static func screenRecordingGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Whether Accessibility is currently granted, without prompting.
    public nonisolated static func accessibilityGranted() -> Bool {
        // The prompt option key is the documented string value of kAXTrustedCheckOptionPrompt.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
    }

    /// Reads both permissions without prompting.
    public func state() -> PermissionState {
        PermissionState(
            screenRecording: Self.screenRecordingGranted(),
            accessibility: Self.accessibilityGranted()
        )
    }

    /// Shows the system prompt for screen recording and returns the answer.
    public func requestScreenRecording() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        permissionsLog.notice("Screen recording request returned \(granted, privacy: .public)")
        return granted
    }

    /// Shows the system prompt for Accessibility and returns the answer.
    public func requestAccessibility() -> Bool {
        // The prompt option key is the documented string value of kAXTrustedCheckOptionPrompt.
        let granted = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
        permissionsLog.notice("Accessibility request returned \(granted, privacy: .public)")
        return granted
    }

    /// Opens the matching Privacy pane in System Settings.
    public func openSystemSettings(for kind: PermissionKind) {
        let anchor =
            switch kind {
            case .screenRecording: "Privacy_ScreenCapture"
            case .accessibility: "Privacy_Accessibility"
            }
        let rawURL = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)"
        guard let url = URL(string: rawURL) else {
            permissionsLog.error("Invalid settings URL for \(kind.rawValue, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Emits the permission state now and again whenever the app becomes active.
    public func updates() -> AsyncStream<PermissionState> {
        if let existing = updatesStream {
            return existing
        }
        let (stream, continuation) = AsyncStream.makeStream(
            of: PermissionState.self,
            bufferingPolicy: .bufferingNewest(4)
        )
        self.updatesStream = stream
        self.continuation = continuation
        installObservers()
        publish(state())
        return stream
    }

    private var updatesStream: AsyncStream<PermissionState>?

    private func installObservers() {
        guard defaultTokens.isEmpty, workspaceTokens.isEmpty else { return }

        let appActive = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
        defaultTokens.append(appActive)

        // Workspace activations also arrive in unbundled tools where no NSApplication exists.
        let workspaceActive = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
        workspaceTokens.append(workspaceActive)
    }

    private func refresh() {
        publish(state())
    }

    private func publish(_ state: PermissionState) {
        guard lastPublished != state else { return }
        lastPublished = state
        continuation?.yield(state)
    }
}
