import Foundation

/// One kept frame and the context that was focused when it was captured.
public struct Moment: Hashable, Identifiable, Sendable {
    public let id: Int64
    public let capturedAt: Date
    public let app: AppRef
    public let windowTitle: String?
    public let url: URL?

    public init(id: Int64, capturedAt: Date, app: AppRef, windowTitle: String?, url: URL?) {
        self.id = id
        self.capturedAt = capturedAt
        self.app = app
        self.windowTitle = windowTitle
        self.url = url
    }
}

/// A lightweight moment reference used by timelines and filmstrips.
public struct MomentStamp: Hashable, Identifiable, Sendable {
    public let id: Int64
    public let capturedAt: Date

    public init(id: Int64, capturedAt: Date) {
        self.id = id
        self.capturedAt = capturedAt
    }
}
