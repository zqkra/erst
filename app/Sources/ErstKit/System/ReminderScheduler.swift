import Foundation
import UserNotifications
import os

private let reminderLog = Logger(subsystem: "app.erst.Erst", category: "ReminderScheduler")

/// Schedules local reminders, and does nothing when the process has no bundle identifier.
public actor ReminderScheduler {
    /// Creates a scheduler. No notification center is touched until a method is called.
    public init() {}

    /// Requests alert and sound authorization. Returns false when unbundled or denied.
    public func requestAuthorization() async -> Bool {
        guard let center = notificationCenter() else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            reminderLog.error(
                "Authorization failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// Schedules a reminder, replacing any pending reminder with the same identifier.
    @discardableResult
    public func schedule(_ reminder: ReminderRequest) async -> Bool {
        guard let center = notificationCenter() else { return false }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default

        if let attachmentURL = reminder.attachmentImageURL {
            do {
                let attachment = try UNNotificationAttachment(
                    identifier: "\(reminder.identifier).image",
                    url: attachmentURL
                )
                content.attachments = [attachment]
            } catch {
                reminderLog.error(
                    "Attachment failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        // The app also delivers overdue reminders after sleep or relaunch.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, reminder.date.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(
            identifier: reminder.identifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            return true
        } catch {
            let message =
                "Scheduling \(reminder.identifier) failed: "
                + "\(error.localizedDescription)"
            reminderLog.error("\(message, privacy: .public)")
            return false
        }
    }

    /// Removes a pending or delivered reminder.
    public func cancel(identifier: String) {
        guard let center = notificationCenter() else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func notificationCenter() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else {
            reminderLog.notice("Skipping notifications because the process is unbundled")
            return nil
        }
        return UNUserNotificationCenter.current()
    }
}
