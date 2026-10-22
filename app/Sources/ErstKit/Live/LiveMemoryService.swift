import CoreGraphics
import ErstCore
import ErstModel
import Foundation
import os

let liveMemoryLog = Logger(subsystem: "app.erst.Erst", category: "LiveMemoryService")

/// The production service shared by every app surface.
public actor LiveMemoryService: MemoryService {
    public nonisolated let dataDirectory: URL
    public nonisolated var status: AsyncStream<RecorderStatus> { broadcast.stream() }
    let engine: LiveEngine
    let reader = FrameReader()
    let broadcast = RecorderStatusBroadcast()
    var recorder: Recorder?
    var stateTask: Task<Void, Never>?
    var userPaused = false
    var pauseUntil: Date?
    var shuttingDown = false
    var mutationBusy = false
    var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    var imageGeneration: UInt64 = 0
    let images = NSCache<NSString, LiveImage>()

    public init(engine: LiveEngine, dataDirectory: URL) {
        self.engine = engine
        self.dataDirectory = dataDirectory
        images.totalCostLimit = 48 * 1024 * 1024
        images.countLimit = 80
    }

    public func timeline(in range: ClosedRange<Date>, buckets: Int) async throws -> TimelineSlice {
        try await engine.call {
            FfiConversions.timeline(
                try $0.timeline(
                    startMs: FfiConversions.milliseconds(range.lowerBound),
                    endMs: FfiConversions.milliseconds(range.upperBound),
                    buckets: UInt32(clamping: max(1, buckets))))
        }
    }

    public func timelineTrack(in range: ClosedRange<Date>) async throws -> TimelineTrack {
        try await engine.call {
            FfiConversions.track(
                try $0.timelineTrack(
                    startMs: FfiConversions.milliseconds(range.lowerBound),
                    endMs: FfiConversions.milliseconds(range.upperBound)))
        }
    }

    public func hourlyHeat(in range: ClosedRange<Date>) async throws -> [DayHeat] {
        try await engine.call {
            try $0.hourlyHeat(
                startMs: FfiConversions.milliseconds(range.lowerBound),
                endMs: FfiConversions.milliseconds(range.upperBound),
                timeZone: FfiConversions.timeZoneIdentifier
            ).map(FfiConversions.dayHeat)
        }
    }

    public func moment(id: Moment.ID) async throws -> MomentDetail {
        try await engine.call { engine in
            let timeZone = FfiConversions.timeZoneIdentifier
            let value = try engine.moment(frameId: id, timeZone: timeZone)
            let neighbors = try value.neighbors.map {
                FfiConversions.moment(
                    try engine.moment(frameId: $0.id, timeZone: timeZone))
            }
            let onScreen: ClosedRange<Date>?
            if let start = value.onScreenFromMs, let end = value.onScreenToMs {
                onScreen = FfiConversions.range(start, end)
            } else {
                onScreen = nil
            }
            return MomentDetail(
                moment: FfiConversions.moment(value), lines: value.lines.map(FfiConversions.line),
                onScreen: onScreen, visitsToday: Int(value.visitsToday),
                lastOpened: value.lastOpenedMs.map(FfiConversions.date), neighbors: neighbors)
        }
    }

    public func nearestMoment(to date: Date) async throws -> Moment? {
        try await engine.call { engine in
            guard let stamp = try engine.nearestMoment(atMs: FfiConversions.milliseconds(date)) else {
                return nil
            }
            return FfiConversions.moment(
                try engine.moment(frameId: stamp.id, timeZone: FfiConversions.timeZoneIdentifier))
        }
    }

    public func search(_ query: SearchQuery, limit: Int) async throws -> [SearchHit] {
        guard limit > 0 else { return [] }
        return try await engine.call {
            let timeZone = TimeZone.current
            return try $0.search(
                query: SearchSyntax.encode(query, in: timeZone), limit: UInt32(clamping: limit),
                timeZone: timeZone.identifier
            ).map(FfiConversions.hit)
        }
    }

    public func activity(in range: ClosedRange<Date>) async throws -> ActivityReport {
        try await engine.call {
            FfiConversions.activity(
                try $0.activity(
                    startMs: FfiConversions.milliseconds(range.lowerBound),
                    endMs: FfiConversions.milliseconds(range.upperBound),
                    timeZone: FfiConversions.timeZoneIdentifier))
        }
    }

    public func todaySummary() async throws -> TodaySummary {
        let now = Date()
        let range = Calendar.current.startOfDay(for: now)...now
        return try await engine.call {
            FfiConversions.today(
                try $0.todaySummary(
                    nowMs: FfiConversions.milliseconds(now),
                    timeZone: FfiConversions.timeZoneIdentifier, buckets: 48),
                range: range)
        }
    }

    public func storage() async throws -> StorageReport {
        try await engine.call {
            let today = try $0.todaySummary(
                nowMs: FfiConversions.milliseconds(Date()),
                timeZone: FfiConversions.timeZoneIdentifier, buckets: 1)
            return FfiConversions.storage(try $0.storage(), todayBytes: Int64(clamping: today.keptBytes))
        }
    }

    public func image(for moment: Moment.ID, maxPixelSize: Int) async throws -> CGImage {
        let generation = imageGeneration
        let size = max(32, maxPixelSize)
        let key = "\(moment):\(size)" as NSString
        if let image = images.object(forKey: key) { return image.image }
        let image: CGImage
        if let recent = await recorder?.recentFrame(id: moment) {
            image = try LiveImage.scaled(recent, maximum: size)
        } else {
            let value = try await engine.call {
                try $0.moment(frameId: moment, timeZone: FfiConversions.timeZoneIdentifier)
            }
            guard let path = value.segmentPath else { throw LiveMemoryError.imageUnavailable }
            // The engine answers absolute paths, so never resolve them against the data directory.
            image = try await reader.image(
                for: URL(filePath: path), ptsMilliseconds: value.ptsMs, maxPixelSize: size)
        }
        guard generation == imageGeneration else { throw LiveMemoryError.historyChanged }
        images.setObject(LiveImage(image), forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    /// Uses the recorder's cache while the newest video segment is still open.
    public func latestImage() async throws -> CGImage? {
        let generation = imageGeneration
        if let frame = await recorder?.latestFrame(), generation == imageGeneration { return frame.image }
        guard let moment = try await nearestMoment(to: Date()) else { return nil }
        return try await image(for: moment.id, maxPixelSize: 1280)
    }

    public func addReminder(for moment: Moment.ID?, at date: Date, note: String) async throws {
        try await engine.call {
            _ = try $0.addReminder(frameId: moment, dueAtMs: FfiConversions.milliseconds(date), note: note)
        }
    }

    func acquireMutation() async {
        if !mutationBusy {
            mutationBusy = true
            return
        }
        await withCheckedContinuation { mutationWaiters.append($0) }
    }

    func releaseMutation() {
        if mutationWaiters.isEmpty { mutationBusy = false } else { mutationWaiters.removeFirst().resume() }
    }

    /// Reports deleted videos whose files are still on disk.
    ///
    /// Erase and retention succeed once the database commits. A video the file
    /// system refuses to delete stays queued, and the next maintenance pass
    /// retries it. A count above zero means that retry has not worked yet.
    func logPendingFileDeletions() async {
        guard let count = try? await engine.call({ try $0.pendingFileCount() }), count > 0 else { return }
        liveMemoryLog.notice(
            "\(count, privacy: .public) deleted videos could not be removed and stay queued")
    }
}
