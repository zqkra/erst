import CoreGraphics
import Foundation

extension Recorder {
    /// Starts focus tracking and screen capture. Missing permission sets `.needsPermission`.
    public func start() async {
        guard !started, !stopping else { return }
        guard Permissions.screenRecordingGranted() else {
            status = .needsPermission
            publishState()
            recorderLog.error(
                "Screen Recording permission is missing. Grant it in System Settings, then restart."
            )
            return
        }
        started = true
        // The first Vision request after launch compiles its models for half a minute.
        // Start it now, in the background, so the first kept frame does not pay for it.
        await ocrQueue.warmUp()
        isSystemActive = await activityMonitor.start()
        startActivityConsumer()
        await captureService.setSystemActive(isSystemActive)
        await focusTracker.start()
        guard !stopping else {
            await focusTracker.stop()
            return
        }
        focus = await focusTracker.currentContext()
        startFocusConsumer()
        status = isSystemActive ? .recording : .paused(until: nil)
        publishState()
        do {
            try await captureService.start()
        } catch {
            recorderLog.error(
                "Capture did not start: \(error.localizedDescription, privacy: .public)"
            )
            if let captureError = error as? CaptureError, captureError == .permissionDenied {
                status = .needsPermission
            } else {
                status = .stopped
            }
            publishState()
            focusTask?.cancel()
            await focusTracker.stop()
            return
        }
        guard !stopping else {
            await captureService.stop()
            return
        }
        startCaptureConsumer()
        beginSpan(at: Date())
    }

    /// Stops capture, finishes the segment, and closes the state stream.
    public func stop() async {
        guard !stopping else { return }
        if !started {
            stopping = true
            status = .stopped
            publishState()
            continuation.finish()
            return
        }
        stopping = true
        status = .stopped
        publishState()
        resumeTask?.cancel()
        resumeTask = nil
        await activityMonitor.stop()
        activityTask?.cancel()
        await activityTask?.value
        activityTask = nil
        await captureService.stop()
        captureTask?.cancel()
        await captureTask?.value
        captureTask = nil
        focusTask?.cancel()
        await focusTracker.stop()
        await focusTask?.value
        focusTask = nil
        endSpan(at: Date())
        await finishOpenSegment()
        publishState()
        continuation.finish()
    }

    /// Replaces the excluded apps for future frames, spans, and the content filter.
    public func updateExcludedBundleIDs(_ bundleIDs: Set<String>) async {
        configuration.excludedBundleIDs = bundleIDs
        excludedBundleIDs = bundleIDs
        if let focus, isExcluded(focus.bundleID) { endSpan(at: Date()) }
        await captureService.updateContentFilter(excluding: bundleIDs)
        beginSpan(at: Date())
    }

    /// Applies interval and exclusions to the live stream, and compression to the next segment.
    public func apply(_ configuration: RecorderConfiguration) async {
        self.configuration = configuration
        excludedBundleIDs = configuration.excludedBundleIDs
        if let focus, isExcluded(focus.bundleID) { endSpan(at: Date()) }
        await segmentWriter.apply(
            compression: configuration.compression, segmentDuration: configuration.segmentDuration)
        await focusTracker.updateIdleThreshold(configuration.idleThreshold)
        await captureService.apply(
            CaptureServiceConfiguration(
                captureInterval: configuration.captureInterval,
                excludedBundleIDs: configuration.excludedBundleIDs
            ))
        beginSpan(at: Date())
    }

    private func startFocusConsumer() {
        focusTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.focusTracker.events {
                await self.handleFocus(event)
            }
        }
    }

    private func handleFocus(_ event: FocusEvent) {
        guard !isStopped else { return }
        switch event {
        case .changed(let context):
            focus = context
            guard case .recording = status, !isIdle else { return }
            endSpan(at: context.at)
            beginSpan(at: context.at)
        case .idle(let since):
            isIdle = true
            guard case .recording = status else { return }
            endSpan(at: since)
        case .resumed(let at):
            isIdle = false
            guard case .recording = status else { return }
            beginSpan(at: at)
        }
    }

    private func startActivityConsumer() {
        activityTask = Task { [weak self, activityMonitor] in
            for await active in activityMonitor.changes {
                guard !Task.isCancelled else { return }
                await self?.systemActivityChanged(active)
            }
        }
    }

    private func systemActivityChanged(_ active: Bool) async {
        guard started, !stopping else { return }
        isSystemActive = active
        if !active {
            if case .recording = status { status = .paused(until: nil) }
            endSpan(at: Date())
            publishState()
        } else if !isUserPaused {
            resumeFromPause()
        } else {
            status = .paused(until: userPauseUntil)
            publishState()
        }
        await captureService.setSystemActive(active)
    }
}
