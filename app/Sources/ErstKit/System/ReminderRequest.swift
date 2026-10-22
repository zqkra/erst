import Foundation

/// A local notification request for a moment or a note.
public struct ReminderRequest: Sendable, Equatable {
    /// Stable identifier, also used to replace or cancel a pending reminder.
    public let identifier: String
    /// Notification title.
    public let title: String
    /// Notification body.
    public let body: String
    /// When the notification should be delivered.
    public let date: Date
    /// Optional image shown as a notification attachment.
    public let attachmentImageURL: URL?

    /// Creates a reminder request.
    public init(
        identifier: String,
        title: String,
        body: String,
        date: Date,
        attachmentImageURL: URL? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.date = date
        self.attachmentImageURL = attachmentImageURL
    }
}
