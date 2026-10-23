import CoreGraphics
import Foundation
import os

let recorderLog = Logger(subsystem: "app.erst.Erst", category: "Recorder")

/// Wires capture, change detection, encoding, OCR, focus, and persistence together.
public actor Recorder {
    /// Recorder states, newest first when the consumer falls behind.
    public nonisolated let states: AsyncStream<RecorderState>

    var configuration: RecorderConfiguration
    let keepEvaluator: any KeepEvaluator
    let captureService: CaptureService
    let segmentWriter: SegmentWriter
    var thumbnailer: Thumbnailer
    let ocrQueue: OCRQueue
    let accessibilityText = AccessibilityTextReader()
    let focusTracker: FocusTracker
    let continuation: AsyncStream<RecorderState>.Continuation
    var spans: SpanTracker
    var memory: RecordingMemory
    let activityMonitor = SystemActivityMonitor()
    var activityTask: Task<Void, Never>?
    var isSystemActive = true
    var isUserPaused = false
    var userPauseUntil: Date?
    var pipelineBusy = false
    var pipelineWaiters: [CheckedContinuation<Void, Never>] = []
    /// What the frame in the pipeline is waiting on, for the log when a frame takes too long.
    var pipelineStage = "idle"

    var excludedBundleIDs: Set<String>
    var status: RecorderState.Status = .stopped
    var framesSeen = 0
    var framesKept = 0
    var lastKeptAt: Date?
    var focus: FocusContext?
    var lastKeptFocus: FocusContext?
    var isIdle = false
    var lastKeptDisplayID: CGDirectDisplayID?

    var captureTask: Task<Void, Never>?
    var focusTask: Task<Void, Never>?
    var resumeTask: Task<Void, Never>?
    var nextPendingID: UInt64 = 1
    var thumbnailMilliseconds = 0.0
    var accessibilityReads = 0
    var accessibilityMilliseconds = 0.0
    var accessibilityLines = 0
    var accessibilityTruncatedReads = 0
    var ocrLinesReplaced = 0

    var started = false
    var stopping = false

    /// Creates a recorder that writes into the given data directory.
    public init(
        dataDirectory: URL,
        keepEvaluator: any KeepEvaluator,
        memoryWriter: any MemoryWriter,
        configuration: RecorderConfiguration = RecorderConfiguration()
    ) {
        self.configuration = configuration
        self.keepEvaluator = keepEvaluator
        self.memory = RecordingMemory(writer: memoryWriter)
        self.excludedBundleIDs = configuration.excludedBundleIDs
        self.captureService = CaptureService(
            configuration: CaptureServiceConfiguration(
                captureInterval: configuration.captureInterval,
                excludedBundleIDs: configuration.excludedBundleIDs
            )
        )
        self.segmentWriter = SegmentWriter(
            dataDirectory: dataDirectory,
            compression: configuration.compression,
            segmentDuration: configuration.segmentDuration
        )
        self.thumbnailer = Thumbnailer()
        self.ocrQueue = OCRQueue(recognizer: TextRecognizer())
        self.focusTracker = FocusTracker(idleThreshold: configuration.idleThreshold)
        let (stream, continuation) = AsyncStream.makeStream(
            of: RecorderState.self,
            bufferingPolicy: .bufferingNewest(16)
        )
        self.states = stream
        self.continuation = continuation
        self.spans = SpanTracker(memoryWriter: memoryWriter)
        continuation.yield(
            RecorderState(
                status: .stopped,
                framesSeen: 0,
                framesKept: 0,
                lastKeptAt: nil
            )
        )
    }

    /// The latest state snapshot.
    public func currentState() -> RecorderState {
        RecorderState(
            status: status,
            framesSeen: framesSeen,
            framesKept: framesKept,
            lastKeptAt: lastKeptAt
        )
    }

    /// The latest metrics snapshot.
    public func metrics() async -> RecorderMetrics {
        let ocr = await ocrQueue.metrics()
        return RecorderMetrics(
            framesSeen: framesSeen,
            framesKept: framesKept,
            ocrJobs: ocr.jobs,
            ocrLines: ocr.lines,
            ocrMilliseconds: ocr.milliseconds,
            thumbnailMilliseconds: thumbnailMilliseconds,
            ocrWarmUpMilliseconds: ocr.warmUpMilliseconds,
            accessibilityReads: accessibilityReads,
            accessibilityMilliseconds: accessibilityMilliseconds,
            accessibilityLines: accessibilityLines,
            accessibilityTruncatedReads: accessibilityTruncatedReads,
            ocrLinesReplaced: ocrLinesReplaced
        )
    }

    func isExcluded(_ bundleID: String) -> Bool {
        excludedBundleIDs.contains(bundleID)
    }

    /// Whether the app in front is Erst itself. The capture hides Erst's windows, so a frame or a
    /// span taken while Erst is in front records nothing new and would add Erst to the timeline
    /// and to the time spent per app.
    func isErstItself(_ bundleID: String) -> Bool {
        bundleID == Bundle.main.bundleIdentifier || bundleID.hasPrefix(Self.erstBundleIDPrefix)
    }

    private static let erstBundleIDPrefix = "app.erst."

    var isStopped: Bool {
        if case .stopped = status {
            return true
        }
        return false
    }

    func publishState() {
        continuation.yield(currentState())
    }
}
