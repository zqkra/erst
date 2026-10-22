import Foundation

/// The frontmost app, window title, and browser URL at one instant.
public struct FocusContext: Sendable, Equatable {
    /// Bundle identifier of the frontmost app.
    public let bundleID: String
    /// Display name of the frontmost app.
    public let appName: String
    /// Process of the frontmost app, for reading its accessibility tree.
    public let processID: pid_t
    /// Focused window title when Accessibility is available.
    public let windowTitle: String?
    /// Browser URL when the focused web area exposes one.
    public let url: URL?
    /// When this context was observed.
    public let at: Date

    /// Creates a focus context.
    public init(
        bundleID: String,
        appName: String,
        processID: pid_t,
        windowTitle: String?,
        url: URL?,
        at: Date
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.processID = processID
        self.windowTitle = windowTitle
        self.url = url
        self.at = at
    }

    /// Whether two contexts describe the same app, window, and page.
    public func hasSameIdentity(as other: FocusContext) -> Bool {
        bundleID == other.bundleID
            && windowTitle == other.windowTitle
            && url == other.url
    }
}
