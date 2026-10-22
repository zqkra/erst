import Foundation

/// What to look for on screen. The engine applies the filters before the result limit.
public struct SearchQuery: Hashable, Sendable {
    public var text: String
    public var app: AppRef?
    public var range: ClosedRange<Date>?

    public init(text: String, app: AppRef? = nil, range: ClosedRange<Date>? = nil) {
        self.text = text
        self.app = app
        self.range = range
    }
}
