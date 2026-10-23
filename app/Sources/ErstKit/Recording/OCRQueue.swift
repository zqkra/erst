import CoreVideo
import Foundation
import os

private let ocrQueueLog = Logger(subsystem: "app.erst.Erst", category: "OCRQueue")

/// Runs text recognition on kept frames and keeps their text in capture order.
///
/// After warm-up it keeps one running job and one replaceable pending job, so new frames
/// never cancel active OCR. Before warm-up it holds jobs in a bounded backlog instead,
/// because the first Vision request after launch is the one that compiles its models.
actor OCRQueue {
    typealias Completion = @Sendable (QueuedFrame, [RecognizedLine]) async -> Void

    private struct Job {
        let frame: QueuedFrame
        /// Memory the pixel buffer holds, so the backlog is bounded in bytes.
        let bytes: Int
        let completion: Completion
    }

    /// Pixel-buffer bytes held while Vision's models are still loading.
    ///
    /// A frame count does not bound memory, because a 2560x1440 BGRA frame is 14.7 MB and a
    /// 5K frame is 59 MB. This limit holds six frames at 2560x1440 and one at 5K, which keeps
    /// the backlog inside the app's 150 MB memory budget. Once the models are ready, the
    /// backlog drains in capture order and its memory is released.
    private static let warmUpBacklogByteLimit = 96 * 1_000_000
    /// Recognitions that must fail in a row before the queue leaves Vision alone for a while.
    private static let failuresBeforePause = 3
    /// How long to wait after repeated failures. A host whose text image reader cannot load
    /// (TextRecognition's CRImageReaderError) recompiles its models on every request, so
    /// retrying each kept frame turns one broken request into a compiler loop that takes the
    /// machine down with it. Pausing loses the text of a few frames, nothing more.
    private static let pauseAfterFailures = Duration.seconds(60)
    /// A read takes well under a second once the models are warm, and a first read at the fast
    /// level loads its model in seconds. One that has not finished by now is stuck inside Vision,
    /// which has happened on macOS 27: the frame is stored without text instead of holding
    /// every later frame back.
    private static let recognitionDeadline = Duration.seconds(60)
    /// How long to leave Vision alone after a read got stuck, before a new reader tries again.
    /// It doubles with each stuck read of the run, up to an hour, because a stuck read keeps its
    /// thread and its frame copy for good.
    private static let pauseAfterHang = Duration.seconds(300)
    private static let longestPauseAfterHang = Duration.seconds(3600)
    /// After this many stuck reads, Vision is broken on this host until it restarts: the queue
    /// stops reading text for the rest of the run, so stuck reads cannot pile up threads and
    /// memory. Frames are still recorded, without text.
    private static let stuckReadsBeforeStopping = 6

    private let recognizer: TextRecognizer
    private var active: Job?
    private var pending: Job?
    private var backlog: [Job] = []
    private var task: Task<Void, Never>?
    private var warmUpTask: Task<Void, Never>?
    private var isWarm = false
    private var warmUpMilliseconds: Double?
    private var loggedBacklogDrop = false
    private var loggedPause = false
    private var consecutiveFailures = 0
    private var stuckReads = 0
    private var pausedUntil: ContinuousClock.Instant?
    private var suppressedID: UInt64?
    private var jobs = 0
    private var lines = 0
    private var milliseconds = 0.0
    /// The last frame read and the text it held, so the next frame reads only what changed. Nil
    /// after a failure, so the next frame reads whole.
    private var baseline: (signature: TileSignature, lines: [RecognizedLine])?
    /// When the queue last had to store a waiting frame without text because a newer one came.
    private var lastDrop: ContinuousClock.Instant?

    /// Reads run at background priority, on the efficiency cores: the same lines for about a
    /// fifth of the energy (61 to 72 mJ against 319 to 336 mJ per 1440p read), in about three
    /// times the time. After the queue had to drop a frame, reads run at utility priority for
    /// this long, so a busy machine never costs a frame its text.
    private static let urgentAfterDrop = Duration.seconds(30)

    /// Bytes held by the backlog. Summed on demand, so it cannot drift from the jobs it counts.
    private var backlogBytes: Int {
        backlog.reduce(0) { $0 + $1.bytes }
    }

    init(recognizer: TextRecognizer) {
        self.recognizer = recognizer
    }

    /// Starts the process-wide Vision warm-up. Safe to call more than once.
    func warmUp() {
        guard !isWarm, warmUpTask == nil else { return }
        warmUpTask = Task(priority: .utility) { [weak self] in
            let elapsed = await TextRecognizer.warmUp()
            await self?.finishWarmUp(after: elapsed)
        }
    }

    func enqueue(_ frame: QueuedFrame, completion: @escaping Completion) async {
        let job = Job(
            frame: frame,
            bytes: Self.byteCount(of: frame.frame.pixelBuffer),
            completion: completion
        )
        if isPaused {
            await storeWithoutText(job)
            return
        }
        guard isWarm else {
            warmUp()
            await admitToBacklog(job)
            return
        }
        guard active != nil || !backlog.isEmpty else {
            start(job)
            return
        }
        if let older = pending {
            pending = job
            lastDrop = .now
            ocrQueueLog.debug("A waiting frame was stored without text; reading at utility priority")
            await older.completion(older.frame, [])
        } else {
            pending = job
        }
    }

    func finishPending() async {
        // Segment finalization must retain text for frames held behind the cold model too.
        while true {
            if let warmUpTask {
                await warmUpTask.value
                continue
            }
            if let task {
                await task.value
                continue
            }
            guard active != nil || pending != nil || !backlog.isEmpty else { return }
            await Task.yield()
        }
    }

    func discardPending(capturedIn range: ClosedRange<Date>) {
        backlog.removeAll { range.contains($0.frame.frame.capturedAt) }
        if let pending, range.contains(pending.frame.frame.capturedAt) {
            self.pending = nil
        }
        if let active, range.contains(active.frame.frame.capturedAt) {
            task?.cancel()
            suppressedID = active.frame.id
        }
    }

    func metrics() -> (jobs: Int, lines: Int, milliseconds: Double, warmUpMilliseconds: Double?) {
        (jobs, lines, milliseconds, warmUpMilliseconds)
    }

    /// Holds a frame until the models are ready. When the byte limit is full, the oldest
    /// frames are stored without text first, so the backlog keeps the most recent screens.
    private func admitToBacklog(_ job: Job) async {
        // A frame that cannot fit even alone is refused. Older frames stay, because evicting
        // them would not make room for a frame that is larger than the whole limit.
        guard job.bytes <= Self.warmUpBacklogByteLimit else {
            logBacklogDrop()
            await storeWithoutText(job)
            return
        }
        var evicted: [Job] = []
        while !backlog.isEmpty, backlogBytes + job.bytes > Self.warmUpBacklogByteLimit {
            evicted.append(backlog.removeFirst())
        }
        backlog.append(job)
        if !evicted.isEmpty { logBacklogDrop() }
        for dropped in evicted {
            await storeWithoutText(dropped)
        }
    }

    private func logBacklogDrop() {
        guard !loggedBacklogDrop else { return }
        loggedBacklogDrop = true
        ocrQueueLog.debug("OCR backlog reached its byte limit; storing a frame without text")
    }

    /// Stores a frame without text, the same tradeoff the pending slot makes after warm-up.
    private func storeWithoutText(_ job: Job) async {
        await job.completion(job.frame, [])
    }

    private func finishWarmUp(after milliseconds: Double) {
        isWarm = true
        warmUpMilliseconds = milliseconds
        warmUpTask = nil
        let queued = backlog.count
        let timing = String(format: "%.0f", milliseconds)
        ocrQueueLog.notice(
            "Text recognition is warm after \(timing, privacy: .public) ms; draining \(queued) queued frames"
        )
        advance()
    }

    /// Starts the next queued job. The backlog drains in capture order before the pending slot.
    private func advance() {
        guard isWarm, active == nil else { return }
        if !backlog.isEmpty {
            start(backlog.removeFirst())
        } else if let next = pending {
            pending = nil
            start(next)
        }
    }

    private func start(_ job: Job) {
        active = job
        guard !isPaused else {
            // A frame that waited while recognition stopped gets no text, like every frame of the
            // pause. It goes through `complete` so a drain still waits for it.
            task = Task { [weak self] in
                await self?.complete(job, lines: [], reading: nil, elapsedMilliseconds: 0)
            }
            return
        }
        let signature = TileSignature(job.frame.frame.pixelBuffer)
        let plan = readPlan(for: signature)
        let recognizer = recognizer
        task = Task(priority: readPriority) { [weak self] in
            guard let self else { return }
            let start = ContinuousClock.now
            var recognized: [RecognizedLine] = []
            var succeeded = false
            do {
                if plan?.regions.isEmpty != true {
                    let frame = job.frame
                    let regions = plan?.regions.map(\.read)
                    let lines = try await Deadline.run(within: Self.recognitionDeadline) {
                        try await recognizer.recognizeText(in: frame.frame.pixelBuffer, regions: regions)
                    }
                    guard let lines else {
                        await self.pauseAfterStuckRead()
                        await self.complete(job, lines: [], reading: nil, elapsedMilliseconds: 0)
                        return
                    }
                    recognized = lines
                }
                await self.noteRecognitionFinished(failed: false)
                succeeded = true
            } catch {
                await self.noteRecognitionFinished(failed: true)
                ocrQueueLog.error(
                    "Text recognition failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            let elapsed = start.duration(to: ContinuousClock.now) / .milliseconds(1)
            await self.complete(
                job, lines: recognized, reading: succeeded ? (signature, plan) : nil,
                elapsedMilliseconds: elapsed)
        }
    }

    private var isPaused: Bool {
        guard stuckReads < Self.stuckReadsBeforeStopping else { return true }
        return pausedUntil.map { ContinuousClock.now < $0 } ?? false
    }

    private var readPriority: TaskPriority {
        guard let lastDrop, lastDrop.duration(to: .now) < Self.urgentAfterDrop else { return .background }
        return .utility
    }

    /// What to read of a frame: nil for all of it, which is the first frame, a frame of another
    /// size, or a frame that changed almost everywhere.
    private func readPlan(for signature: TileSignature?) -> ReadPlan? {
        guard let signature, let baseline,
            let changed = signature.changedTiles(since: baseline.signature)
        else { return nil }
        return ReadPlan.make(changed: changed, signature: signature, previousLines: baseline.lines)
    }

    /// Gives up on a read stuck inside Vision: reading starts again after a pause, and the frames
    /// in between are stored without text. The stuck call holds only its own GCD thread, so the
    /// recognizer stays usable.
    private func pauseAfterStuckRead() {
        baseline = nil
        consecutiveFailures = 0
        stuckReads += 1
        let seconds = Int(Self.recognitionDeadline.components.seconds)
        guard stuckReads < Self.stuckReadsBeforeStopping else {
            ocrQueueLog.error(
                "Text recognition did not finish in \(seconds, privacy: .public) s, \(self.stuckReads, privacy: .public) times; no more text is read until Erst restarts"
            )
            return
        }
        let pause = min(Self.pauseAfterHang * (1 << (stuckReads - 1)), Self.longestPauseAfterHang)
        pausedUntil = ContinuousClock.now.advanced(by: pause)
        ocrQueueLog.error(
            "Text recognition did not finish in \(seconds, privacy: .public) s; pausing it for \(Int(pause.components.seconds), privacy: .public) s"
        )
    }

    /// Counts a run of failures and pauses recognition before it becomes a compiler loop.
    private func noteRecognitionFinished(failed: Bool) {
        guard failed else {
            consecutiveFailures = 0
            pausedUntil = nil
            loggedPause = false
            return
        }
        consecutiveFailures += 1
        guard consecutiveFailures >= Self.failuresBeforePause else { return }
        consecutiveFailures = 0
        pausedUntil = ContinuousClock.now.advanced(by: Self.pauseAfterFailures)
        guard !loggedPause else { return }
        loggedPause = true
        let seconds = Int(Self.pauseAfterFailures.components.seconds)
        ocrQueueLog.notice(
            "Pausing text recognition for \(seconds, privacy: .public) s after repeated failures"
        )
    }

    /// `reading` is the frame's signature and plan when recognition succeeded, nil when it failed.
    private func complete(
        _ job: Job,
        lines read: [RecognizedLine],
        reading: Reading?,
        elapsedMilliseconds: Double
    ) async {
        guard let active, active.frame.id == job.frame.id else { return }
        let recognized = frameText(read, reading: reading)
        let regions = reading?.plan.map { "\($0.regions.count) regions" } ?? "whole frame"
        ocrQueueLog.debug(
            "Read \(regions, privacy: .public) in \(Int(elapsedMilliseconds)) ms, \(recognized.count) lines")
        let suppressed = suppressedID == job.frame.id
        jobs += 1
        lines += suppressed ? 0 : recognized.count
        milliseconds += elapsedMilliseconds
        if !suppressed {
            OCRMeasurement.observer?(
                OCRMeasurement(
                    capturedAt: job.frame.frame.capturedAt,
                    lineCount: recognized.count,
                    milliseconds: elapsedMilliseconds
                ))
            await job.completion(job.frame, recognized)
        }
        // Keep the task visible until persistence finishes so a drain cannot flush empty text.
        self.active = nil
        task = nil
        suppressedID = nil
        advance()
    }

    typealias Reading = (signature: TileSignature?, plan: ReadPlan?)

    /// The frame's text: what was read, with the last frame's text outside the changed parts. It
    /// becomes the baseline for the next frame when the read succeeded.
    private func frameText(_ read: [RecognizedLine], reading: Reading?) -> [RecognizedLine] {
        var text = read
        if let plan = reading?.plan, let baseline {
            text = plan.merge(previous: baseline.lines, recognized: read)
        }
        baseline = reading?.signature.map { ($0, text) }
        return text
    }

    /// Memory the buffer holds. Bytes per row include row padding, which is real memory too.
    private static func byteCount(of pixelBuffer: CVPixelBuffer) -> Int {
        CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer)
    }
}
