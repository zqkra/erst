import Foundation

/// A contiguous visit to one app and window.
public struct AppSegment: Hashable, Identifiable, Sendable {
    public let id: Int64
    public let app: AppRef
    public let windowTitle: String?
    public let range: ClosedRange<Date>

    public init(id: Int64, app: AppRef, windowTitle: String?, range: ClosedRange<Date>) {
        self.id = id
        self.app = app
        self.windowTitle = windowTitle
        self.range = range
    }
}

/// The heat, app visits, and kept frames inside one time range.
public struct TimelineSlice: Hashable, Sendable {
    public let range: ClosedRange<Date>
    public let heat: [UInt8]
    public let segments: [AppSegment]
    public let moments: [MomentStamp]

    public init(range: ClosedRange<Date>, heat: [UInt8], segments: [AppSegment], moments: [MomentStamp]) {
        self.range = range
        self.heat = heat
        self.segments = segments
        self.moments = moments
    }
}
