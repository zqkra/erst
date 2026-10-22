import CoreGraphics
import ErstModel
import Foundation

/// A deterministic everyday dataset so every screen works before the engine is wired.
public final class PreviewMemoryService: MemoryService, @unchecked Sendable {
    private let lock = NSLock()
    private var dataset: PreviewDataset
    private var storedSettings: ErstSettings
    private var imageCache: [String: CGImage] = [:]
    private let statusStream: AsyncStream<RecorderStatus>
    private let statusContinuation: AsyncStream<RecorderStatus>.Continuation

    /// Builds the sample day ending at 17:42 today. Snapshots pass a status and can start empty.
    public init(
        now: Date? = nil,
        status: RecorderStatus = .recording,
        includesHistory: Bool = true
    ) {
        let anchor = now ?? PreviewMemoryService.sampleNow()
        dataset = PreviewDataset(now: anchor, includesHistory: includesHistory)
        storedSettings = .default
        storedSettings.isRecording = status == .recording
        let stream = AsyncStream.makeStream(of: RecorderStatus.self, bufferingPolicy: .bufferingNewest(1))
        statusStream = stream.stream
        statusContinuation = stream.continuation
        stream.continuation.yield(status)
    }

    public var status: AsyncStream<RecorderStatus> { statusStream }

    public var dataDirectory: URL {
        URL.temporaryDirectory.appending(path: "ErstPreview", directoryHint: .isDirectory)
    }

    public func hourlyHeat(in range: ClosedRange<Date>) async throws -> [DayHeat] {
        readDataset().hourlyHeat(in: range)
    }

    public func timeline(in range: ClosedRange<Date>, buckets: Int) async throws -> TimelineSlice {
        readDataset().timeline(in: range, buckets: buckets)
    }

    public func timelineTrack(in range: ClosedRange<Date>) async throws -> TimelineTrack {
        readDataset().track(in: range)
    }

    public func moment(id: Moment.ID) async throws -> MomentDetail {
        guard let record = readDataset().moment(id: id), let detail = readDataset().detail(for: record.moment)
        else {
            throw NSError(domain: "ErstPreview", code: 404)
        }
        return detail
    }

    public func nearestMoment(to date: Date) async throws -> Moment? {
        readDataset().nearest(to: date)
    }

    public func search(_ query: SearchQuery, limit: Int) async throws -> [SearchHit] {
        readDataset().search(query, limit: limit)
    }

    public func erase(_ range: ClosedRange<Date>) async throws {
        eraseData(in: range)
    }

    public func activity(in range: ClosedRange<Date>) async throws -> ActivityReport {
        readDataset().activity(in: range)
    }

    public func todaySummary() async throws -> TodaySummary {
        readDataset().todaySummary()
    }

    public func storage() async throws -> StorageReport {
        StorageReport(
            usedBytes: 2_100_000_000,
            limitBytes: 20_000_000_000,
            screensBytes: 1_820_000_000,
            textBytes: 160_000_000,
            previewsBytes: 120_000_000,
            averagePerDayBytes: 8_000_000,
            keptTodayBytes: 8_400_000
        )
    }

    public func image(for moment: Moment.ID, maxPixelSize: Int) async throws -> CGImage {
        let width = max(320, min(1600, maxPixelSize))
        let key = "\(moment)-\(width)"
        if let cached = cachedImage(for: key) { return cached }
        guard let record = readDataset().moment(id: moment),
            let image = PreviewFrameRenderer.render(moment: record.moment, lines: record.lines, width: width)
        else {
            throw NSError(domain: "ErstPreview", code: 500)
        }
        storeImage(image, for: key)
        return image
    }

    public func settings() async throws -> ErstSettings {
        readSettings()
    }

    public func update(_ settings: ErstSettings) async throws {
        let changed = store(settings)
        if changed {
            statusContinuation.yield(settings.isRecording ? .recording : .stopped)
        }
    }

    public func addReminder(for moment: Moment.ID?, at date: Date, note: String) async throws {}

    public func setRecording(_ isRecording: Bool) async {
        storeRecording(isRecording)
        statusContinuation.yield(isRecording ? .recording : .stopped)
    }

    private func readDataset() -> PreviewDataset {
        lock.lock()
        defer { lock.unlock() }
        return dataset
    }

    private func eraseData(in range: ClosedRange<Date>) {
        lock.lock()
        dataset = dataset.erasing(range)
        imageCache.removeAll()
        lock.unlock()
    }

    private func readSettings() -> ErstSettings {
        lock.lock()
        defer { lock.unlock() }
        return storedSettings
    }

    private func store(_ settings: ErstSettings) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let changed = storedSettings.isRecording != settings.isRecording
        storedSettings = settings
        return changed
    }

    private func storeRecording(_ isRecording: Bool) {
        lock.lock()
        storedSettings.isRecording = isRecording
        lock.unlock()
    }

    private func cachedImage(for key: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return imageCache[key]
    }

    private func storeImage(_ image: CGImage, for key: String) {
        lock.lock()
        imageCache[key] = image
        lock.unlock()
    }

    private static func sampleNow() -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(bySettingHour: 17, minute: 42, second: 8, of: start) ?? Date()
    }
}
