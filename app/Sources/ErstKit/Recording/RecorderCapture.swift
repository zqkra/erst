import CoreGraphics
import Foundation

extension Recorder {
    /// Far longer than any healthy frame, which takes well under a second.
    static let stuckFrameDeadline = Duration.seconds(30)

    func startCaptureConsumer() {
        captureTask = Task { [weak self] in
            guard let self else { return }
            for await frame in self.captureService.frames {
                await self.ingest(frame)
            }
        }
    }

    private func ingest(_ frame: CapturedFrame) async {
        await acquirePipeline()
        defer { releasePipeline() }
        // Capture waits on each frame, so a frame stuck in a step means nothing more is recorded.
        // The log names the step, so a stall is never silent again.
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.stuckFrameDeadline)
            guard !Task.isCancelled else { return }
            await self?.reportStuckFrame()
        }
        defer { watchdog.cancel() }
        await process(frame)
        pipelineStage = "idle"
    }

    private func reportStuckFrame() {
        let seconds = Int(Self.stuckFrameDeadline.components.seconds)
        recorderLog.error(
            "A captured frame is still \(self.pipelineStage, privacy: .public) after \(seconds, privacy: .public) s; nothing new is recorded until it finishes"
        )
    }

    private func process(_ frame: CapturedFrame) async {
        framesSeen += 1
        defer { publishState() }
        guard case .recording = status else { return }
        guard !isIdle, !FocusTracker.isSecureInputActive() else { return }
        guard let focus, !isExcluded(focus.bundleID) else { return }
        nextPendingID &+= 1
        let pendingID = nextPendingID
        memory.register(id: pendingID, capturedAt: frame.capturedAt)
        var enqueued = false
        defer { if !enqueued { memory.remove(id: pendingID) } }

        let thumbnailStart = ContinuousClock.now
        let thumbnail: Thumbnail
        do {
            thumbnail = try thumbnailer.thumbnail(from: frame.pixelBuffer)
        } catch {
            recorderLog.error(
                "Thumbnail failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        thumbnailMilliseconds += milliseconds(since: thumbnailStart)

        guard canKeep(frame, pendingID: pendingID, focus: focus) else { return }
        let focusChanged =
            lastKeptDisplayID != frame.displayID
            || (lastKeptFocus.map { !$0.hasSameIdentity(as: focus) } ?? false)
        let verdict = autoreleasepool {
            keepEvaluator.evaluate(
                thumbnail,
                at: frame.capturedAt,
                focusChanged: focusChanged
            )
        }
        guard verdict.keep else { return }

        let result: AppendResult
        pipelineStage = "writing video"
        do {
            result = try await segmentWriter.append(frame)
        } catch {
            recorderLog.error(
                "Encoding a kept frame failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        if let rotated = result.rotatedFrom {
            memory.finishSegment(rotated)
        }
        guard let segmentID = memory.segmentID(for: result.segment),
            canKeep(frame, pendingID: pendingID, focus: focus)
        else {
            return
        }

        lastKeptDisplayID = frame.displayID
        lastKeptFocus = focus
        lastKeptAt = frame.capturedAt
        framesKept += 1
        // Text recognition reads a copy, so ScreenCaptureKit gets its buffer back even when a
        // read takes long or never returns.
        let queued = QueuedFrame(
            id: pendingID,
            frame: frame.owningCopy(),
            segmentID: segmentID,
            ptsMilliseconds: result.ptsMilliseconds,
            focus: focus,
            changeRatio: verdict.changeRatio
        )
        memory.markQueued(queued)
        enqueued = true
        pipelineStage = "queueing text"
        let reading = Task(priority: .utility) { [accessibilityText] in
            await accessibilityText.read(focus, displayID: frame.displayID)
        }
        await ocrQueue.enqueue(queued) { [weak self] frame, ocrLines in
            let accessibility = await reading.value
            await self?.store(frame, ocr: ocrLines, accessibility: accessibility)
        }
    }

    private func canKeep(_ frame: CapturedFrame, pendingID: UInt64, focus: FocusContext) -> Bool {
        guard case .recording = status else { return false }
        return !stopping && !isIdle && isSystemActive && !FocusTracker.isSecureInputActive()
            && !isExcluded(focus.bundleID) && !isErstItself(focus.bundleID)
            && memory.contains(id: pendingID)
    }

    func acquirePipeline() async {
        if !pipelineBusy {
            pipelineBusy = true
            return
        }
        await withCheckedContinuation { pipelineWaiters.append($0) }
    }

    func releasePipeline() {
        if pipelineWaiters.isEmpty {
            pipelineBusy = false
        } else {
            pipelineWaiters.removeFirst().resume()
        }
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: ContinuousClock.now)
        return Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}
