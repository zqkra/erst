import Foundation

extension Recorder {
    /// Pauses frame processing until the given date, or indefinitely when nil.
    public func pause(until date: Date?) {
        guard started, !stopping, !isStopped else { return }
        isUserPaused = true
        userPauseUntil = date
        status = .paused(until: date)
        endSpan(at: Date())
        publishState()
        resumeTask?.cancel()
        resumeTask = nil
        guard let date else { return }
        let delay = max(0, date.timeIntervalSinceNow)
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.resumeFromPause()
        }
    }

    /// Resumes a user pause when the system session is active.
    public func resume() {
        resumeTask?.cancel()
        resumeTask = nil
        resumeFromPause()
    }

    func resumeFromPause() {
        guard case .paused = status else { return }
        isUserPaused = false
        userPauseUntil = nil
        guard isSystemActive, !stopping else { return }
        status = .recording
        publishState()
        beginSpan(at: Date())
    }

    func beginSpan(at date: Date) {
        guard case .recording = status, !isIdle, let focus else { return }
        guard !isExcluded(focus.bundleID), !isErstItself(focus.bundleID) else { return }
        spans.begin(focus: focus, at: date)
    }

    func endSpan(at date: Date) {
        spans.end(at: date)
    }
}
