import ErstModel
import Foundation

extension LiveMemoryService {
    public func settings() async throws -> ErstSettings {
        var settings = try await engine.call { FfiConversions.settings(try $0.settings()) }
        settings.launchAtLogin = await LoginItem.isEnabled
        return settings
    }

    public func update(_ settings: ErstSettings) async throws {
        await acquireMutation()
        defer { releaseMutation() }
        guard !shuttingDown else { return }
        try await engine.call { try $0.updateSettings(settings: FfiConversions.settings(settings)) }
        let actual = try await engine.call { FfiConversions.settings(try $0.settings()) }
        await LoginItem.setEnabled(actual.launchAtLogin)
        await applyRecording(actual)
    }

    public func setRecording(_ isRecording: Bool) async {
        await acquireMutation()
        defer { releaseMutation() }
        guard !shuttingDown else { return }
        do {
            var settings = try await engine.call { FfiConversions.settings(try $0.settings()) }
            settings.isRecording = isRecording
            let updated = settings
            try await engine.call { try $0.updateSettings(settings: FfiConversions.settings(updated)) }
            userPaused = false
            pauseUntil = nil
            await applyRecording(settings)
            if isRecording { await recorder?.resume() }
        } catch {
            liveMemoryLog.error("Changing recording failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Applies saved preferences after onboarding, or after permission changes.
    public func startIfEnabled() async throws {
        await acquireMutation()
        defer { releaseMutation() }
        guard !shuttingDown else { return }
        let settings = try await engine.call { FfiConversions.settings(try $0.settings()) }
        await LoginItem.setEnabled(settings.launchAtLogin)
        await applyRecording(settings)
    }

    public func pause(until date: Date?) async {
        await acquireMutation()
        defer { releaseMutation() }
        guard recorder != nil, !shuttingDown else { return }
        userPaused = true
        pauseUntil = date
        await recorder?.pause(until: date)
    }

    /// Stops the recorder and drains its open video segment before termination.
    public func shutdown() async {
        await acquireMutation()
        defer { releaseMutation() }
        shuttingDown = true
        await stopRecorder()
    }

    public func erase(_ range: ClosedRange<Date>) async throws {
        await acquireMutation()
        defer { releaseMutation() }
        guard !shuttingDown else { return }
        await recorder?.pause(until: nil)
        await recorder?.discardPending(capturedIn: range)
        await recorder?.finishOpenSegment()
        imageGeneration &+= 1
        images.removeAllObjects()
        do {
            let erased = try await engine.call {
                try $0.erase(
                    startMs: FfiConversions.milliseconds(range.lowerBound),
                    endMs: FfiConversions.milliseconds(range.upperBound))
            }
            await recorder?.discardPending(
                capturedIn: FfiConversions.range(erased.erasedFromMs, erased.erasedToMs))
            if !erased.purgeComplete {
                liveMemoryLog.notice(
                    "Erased text may remain in the database journal until the next erase or retention pass")
            }
            await logPendingFileDeletions()
            await reader.invalidate()
            imageGeneration &+= 1
            images.removeAllObjects()
            await restorePause()
        } catch {
            await restorePause()
            throw error
        }
    }

    private func restorePause() async {
        if userPaused && (pauseUntil.map { $0 > Date() } ?? true) {
            await recorder?.pause(until: pauseUntil)
        } else {
            userPaused = false
            pauseUntil = nil
            await recorder?.resume()
        }
    }

    private func applyRecording(_ settings: ErstSettings) async {
        guard Permissions.screenRecordingGranted() else {
            await stopRecorder()
            broadcast.publish(.needsPermission)
            return
        }
        guard settings.isRecording else {
            await stopRecorder()
            return
        }
        if let recorder, case .stopped = await recorder.currentState().status {
            await stopRecorder()
        }
        if recorder == nil {
            let next = await engine.recorder(at: dataDirectory, settings: settings)
            recorder = next
            stateTask = Task { [broadcast] in
                for await state in next.states {
                    guard !Task.isCancelled else { return }
                    broadcast.publish(FfiConversions.status(state.status))
                }
            }
            await next.start()
            await restorePause()
        } else {
            await recorder?.apply(FfiConversions.configuration(settings))
        }
    }

    private func stopRecorder() async {
        await recorder?.stop()
        stateTask?.cancel()
        await stateTask?.value
        stateTask = nil
        recorder = nil
        broadcast.publish(.stopped)
    }
}
