import ErstKit
import Foundation
import os

private let reminderLoopLog = Logger(subsystem: "app.erst.Erst", category: "ReminderLoop")

@MainActor
final class ReminderLoop {
    private static let intervalSeconds = 60
    private let task: Task<Void, Never>

    init(service: LiveMemoryService, scheduler: ReminderScheduler) {
        task = Task.detached(priority: .utility) {
            do {
                while !Task.isCancelled {
                    do {
                        let reminders = try await service.dueReminders()
                        if !reminders.isEmpty, await scheduler.requestAuthorization() {
                            for reminder in reminders {
                                try Task.checkCancellation()
                                let request = ReminderRequest(
                                    identifier: "erst.reminder.\(reminder.id).\(reminder.momentID ?? 0)",
                                    title: "A moment to return to", body: reminder.note, date: reminder.dueAt)
                                if await scheduler.schedule(request) {
                                    try await service.completeReminder(id: reminder.id)
                                }
                            }
                        }
                    } catch is CancellationError { return } catch {
                        reminderLoopLog.error(
                            "Delivering reminders failed: \(error.localizedDescription, privacy: .public)")
                    }
                    try await Task.sleep(for: .seconds(Self.intervalSeconds))
                }
            } catch is CancellationError {
                return
            } catch {
                reminderLoopLog.error(
                    "Reminder loop stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Stops the loop without waiting for it, for quitting.
    func cancel() {
        task.cancel()
    }
}
