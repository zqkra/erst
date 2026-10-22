import Foundation

/// A kept frame ready to be stored by the memory engine.
public struct RecordedFrame: Sendable, Equatable {
    /// Wall clock time at which the frame was captured.
    public let capturedAt: Date
    /// Database id of the segment that contains the frame.
    public let segmentID: Int64
    /// Presentation time inside the segment, in milliseconds.
    public let ptsMilliseconds: Int64
    /// Bundle identifier of the frontmost app.
    public let bundleID: String
    /// Name of the frontmost app.
    public let appName: String
    /// Focused window title, when available.
    public let windowTitle: String?
    /// Browser URL, when available.
    public let url: URL?
    /// Fraction of the frame that changed.
    public let changeRatio: Float
    /// Recognized text lines, empty when OCR was skipped.
    public let lines: [RecognizedLine]

    /// Creates a recorded frame.
    public init(
        capturedAt: Date,
        segmentID: Int64,
        ptsMilliseconds: Int64,
        bundleID: String,
        appName: String,
        windowTitle: String?,
        url: URL?,
        changeRatio: Float,
        lines: [RecognizedLine]
    ) {
        self.capturedAt = capturedAt
        self.segmentID = segmentID
        self.ptsMilliseconds = ptsMilliseconds
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.changeRatio = changeRatio
        self.lines = lines
    }
}
