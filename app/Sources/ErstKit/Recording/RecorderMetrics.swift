import Foundation

/// Timing and count totals for one recording session.
public struct RecorderMetrics: Sendable, Equatable {
    /// Frames delivered by capture.
    public let framesSeen: Int
    /// Frames kept by the evaluator.
    public let framesKept: Int
    /// OCR attempts, including failed ones.
    public let ocrJobs: Int
    /// Recognized lines across all OCR results.
    public let ocrLines: Int
    /// Total OCR time in milliseconds.
    public let ocrMilliseconds: Double
    /// Total thumbnail time in milliseconds.
    public let thumbnailMilliseconds: Double
    /// Milliseconds until Vision's text models finished loading, nil while they still load.
    public let ocrWarmUpMilliseconds: Double?
    /// Accessibility reads, one per kept frame while recording.
    public let accessibilityReads: Int
    /// Total time spent reading accessibility trees, in milliseconds.
    public let accessibilityMilliseconds: Double
    /// Exact lines read from accessibility trees.
    public let accessibilityLines: Int
    /// Reads a limit stopped before every visible element was seen.
    public let accessibilityTruncatedReads: Int
    /// OCR lines dropped because the accessibility tree already held their text.
    public let ocrLinesReplaced: Int

    /// Creates a metrics snapshot.
    public init(
        framesSeen: Int,
        framesKept: Int,
        ocrJobs: Int,
        ocrLines: Int,
        ocrMilliseconds: Double,
        thumbnailMilliseconds: Double,
        ocrWarmUpMilliseconds: Double? = nil,
        accessibilityReads: Int = 0,
        accessibilityMilliseconds: Double = 0,
        accessibilityLines: Int = 0,
        accessibilityTruncatedReads: Int = 0,
        ocrLinesReplaced: Int = 0
    ) {
        self.framesSeen = framesSeen
        self.framesKept = framesKept
        self.ocrJobs = ocrJobs
        self.ocrLines = ocrLines
        self.ocrMilliseconds = ocrMilliseconds
        self.thumbnailMilliseconds = thumbnailMilliseconds
        self.ocrWarmUpMilliseconds = ocrWarmUpMilliseconds
        self.accessibilityReads = accessibilityReads
        self.accessibilityMilliseconds = accessibilityMilliseconds
        self.accessibilityLines = accessibilityLines
        self.accessibilityTruncatedReads = accessibilityTruncatedReads
        self.ocrLinesReplaced = ocrLinesReplaced
    }

    /// Mean OCR duration per job in milliseconds.
    public var averageOCRMilliseconds: Double {
        ocrJobs > 0 ? ocrMilliseconds / Double(ocrJobs) : 0
    }

    /// Mean thumbnail duration per delivered frame in milliseconds.
    public var averageThumbnailMilliseconds: Double {
        framesSeen > 0 ? thumbnailMilliseconds / Double(framesSeen) : 0
    }

    /// Mean accessibility read duration per read in milliseconds.
    public var averageAccessibilityMilliseconds: Double {
        accessibilityReads > 0 ? accessibilityMilliseconds / Double(accessibilityReads) : 0
    }

    /// Mean exact lines read per accessibility read.
    public var averageAccessibilityLines: Double {
        accessibilityReads > 0 ? Double(accessibilityLines) / Double(accessibilityReads) : 0
    }
}
