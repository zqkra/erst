import AppKit
import CoreGraphics
import Foundation

/// Combines independent inactivity reasons so waking cannot resume a still-locked session.
actor SystemActivityMonitor {
    nonisolated let changes: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    private var inactiveReasons: Set<Reason> = []
    private var workspaceTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []

    private enum Reason: Sendable {
        case sleep, displaySleep, lock, switchedOut, screenSaver
    }

    init() {
        (changes, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
    }

    isolated deinit {
        removeObservers()
    }

    func start() -> Bool {
        guard workspaceTokens.isEmpty else { return inactiveReasons.isEmpty }
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            if session["CGSSessionScreenIsLocked"] as? Bool == true {
                inactiveReasons.insert(.lock)
            }
            if session[kCGSessionOnConsoleKey as String] as? Bool == false {
                inactiveReasons.insert(.switchedOut)
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceEvents: [(Notification.Name, Reason, Bool)] = [
            (NSWorkspace.willSleepNotification, .sleep, false),
            (NSWorkspace.didWakeNotification, .sleep, true),
            (NSWorkspace.screensDidSleepNotification, .displaySleep, false),
            (NSWorkspace.screensDidWakeNotification, .displaySleep, true),
            (NSWorkspace.sessionDidResignActiveNotification, .switchedOut, false),
            (NSWorkspace.sessionDidBecomeActiveNotification, .switchedOut, true),
        ]
        for (name, reason, active) in workspaceEvents {
            workspaceTokens.append(
                workspace.addObserver(forName: name, object: nil, queue: nil) {
                    [weak self] _ in
                    Task { await self?.set(reason, active: active) }
                })
        }
        let distributed = DistributedNotificationCenter.default()
        let distributedEvents: [(String, Reason, Bool)] = [
            ("com.apple.screenIsLocked", .lock, false),
            ("com.apple.screenIsUnlocked", .lock, true),
            ("com.apple.screensaver.didstart", .screenSaver, false),
            ("com.apple.screensaver.didstop", .screenSaver, true),
        ]
        for (name, reason, active) in distributedEvents {
            distributedTokens.append(
                distributed.addObserver(
                    forName: Notification.Name(name), object: nil, queue: nil
                ) { [weak self] _ in
                    Task { await self?.set(reason, active: active) }
                })
        }
        return inactiveReasons.isEmpty
    }

    func stop() {
        removeObservers()
        continuation.finish()
    }

    private func set(_ reason: Reason, active: Bool) {
        guard !workspaceTokens.isEmpty else { return }
        let wasActive = inactiveReasons.isEmpty
        if active {
            inactiveReasons.remove(reason)
        } else {
            inactiveReasons.insert(reason)
        }
        if wasActive != inactiveReasons.isEmpty {
            continuation.yield(inactiveReasons.isEmpty)
        }
    }

    private func removeObservers() {
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        for token in distributedTokens {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        workspaceTokens.removeAll()
        distributedTokens.removeAll()
    }
}
