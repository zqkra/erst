import AppKit
import ErstCore
import ErstKit
import Foundation

/// Posts process-local workspace events without locking, sleeping, or switching the user's Mac.
enum ProbeControls {
    private enum Failure: Error {
        case check(String)
    }

    static func exercise(_ recorder: Recorder, engine: Engine, configuration: RecorderConfiguration)
        async throws
    {
        var changed = configuration
        changed.captureInterval = 0.5
        changed.compression = .smaller
        await recorder.apply(changed)
        await recorder.finishOpenSegment()
        if let latest = await recorder.latestFrame() {
            let capturedAtMs = try await Task.detached {
                try engine.moment(frameId: latest.id, timeZone: "UTC").stamp.capturedAtMs
            }.value
            let capturedAt = Date(timeIntervalSince1970: Double(capturedAtMs) / 1000)
            await recorder.discardPending(
                capturedIn: capturedAt.addingTimeInterval(-0.002)...capturedAt.addingTimeInterval(0.002))
            guard await recorder.recentFrame(id: latest.id) == nil else {
                throw Failure.check("Discard did not remove the cached frame")
            }
            print(
                "Control verification: finalized segment, read cached frame \(latest.id), discarded its cached image"
            )
        }
        await post(NSWorkspace.willSleepNotification)
        try await expect(.paused(until: nil), recorder: recorder)
        await post(NSWorkspace.sessionDidResignActiveNotification)
        try await Task.sleep(for: .milliseconds(100))
        await post(NSWorkspace.didWakeNotification)
        try await Task.sleep(for: .milliseconds(100))
        try await expect(.paused(until: nil), recorder: recorder)
        await recorder.pause(until: nil)
        await post(NSWorkspace.sessionDidBecomeActiveNotification)
        try await Task.sleep(for: .milliseconds(100))
        try await expect(.paused(until: nil), recorder: recorder)
        await recorder.resume()
        try await expect(.recording, recorder: recorder)
        print(
            "Control verification passed: live apply, finalization, cache discard, overlapping system pauses, user pause, resume"
        )
    }

    @MainActor
    private static func post(_ name: Notification.Name) {
        NSWorkspace.shared.notificationCenter.post(name: name, object: NSWorkspace.shared)
    }

    private static func expect(_ status: RecorderState.Status, recorder: Recorder) async throws {
        for _ in 0..<40 {
            if await recorder.currentState().status == status { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure.check("Recorder did not reach \(status)")
    }
}
