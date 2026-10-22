import ErstCore
import Foundation
import os

private let retentionLog = Logger(subsystem: "app.erst.Erst", category: "Retention")

extension LiveMemoryService {
    /// Lets go of decoded frames and video decoders once no surface shows them. Opening again
    /// decodes the one frame it needs in tens of milliseconds; holding them would keep up to 48 MB
    /// of images and four decoders resident while Erst only records.
    public func releaseImageMemory() async {
        images.removeAllObjects()
        await reader.invalidate()
    }

    /// Runs one retention plan sequentially, excluding erase and recorder replacement.
    public func runRetention() async throws {
        await acquireMutation()
        defer { releaseMutation() }
        guard !shuttingDown else { return }
        let actions = try await engine.call {
            try $0.retentionPlan(nowMs: FfiConversions.milliseconds(Date()))
        }
        let reducer = SegmentReducer()
        for action in actions {
            try Task.checkCancellation()
            do {
                let bytes: UInt64?
                switch action.kind {
                case .reduce:
                    guard let path = action.segmentPath else { continue }
                    // The engine answers absolute paths, so never resolve them against the data directory.
                    bytes = UInt64(clamping: try await reducer.reduce(URL(filePath: path)))
                case .deleteVideo, .deleteSegment:
                    bytes = nil
                }
                try await engine.call { try $0.applyRetention(action: action, newBytes: bytes) }
                imageGeneration &+= 1
                images.removeAllObjects()
                await reader.invalidate()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                retentionLog.error(
                    "Segment \(action.segmentId) retention failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        await logPendingFileDeletions()
    }

    public func dueReminders() async throws -> [LiveReminder] {
        try await engine.call {
            try $0.dueReminders(nowMs: FfiConversions.milliseconds(Date())).map {
                LiveReminder(
                    id: $0.id, momentID: $0.frameId, dueAt: FfiConversions.date($0.dueAtMs), note: $0.note)
            }
        }
    }

    public func completeReminder(id: Int64) async throws {
        try await engine.call { try $0.completeReminder(id: id, atMs: FfiConversions.milliseconds(Date())) }
    }
}

/// A due reminder passed to the app's notification loop.
public struct LiveReminder: Sendable {
    public let id: Int64
    public let momentID: Int64?
    public let dueAt: Date
    public let note: String
}
