import AppKit
import Combine
import CoreGraphics
import ErstModel
import Foundation
import Observation

/// State for scrolling back through kept frames one frame at a time.
@MainActor
@Observable
// ObservableObject supports StateObject ownership with the Command Line Tools SDK.
public final class TimelineModel: ObservableObject {
    public private(set) var track: TimelineTrack?
    public private(set) var selectedIndex = 0
    public private(set) var pointsPerFrame: CGFloat
    public private(set) var activeScale: TimelineScale?
    public private(set) var image: CGImage?
    public private(set) var hasLoaded = false
    /// Bumped whenever the playhead must move to `selectedIndex` without the user scrolling.
    public private(set) var scrollGeneration = 0
    public private(set) var isChoosingDate = false
    /// The preset the dock opens on, so a named scale is always selected after a load.
    public static let initialScale: TimelineScale = .sixHours
    private var appliedInitialScale = false
    /// The width frames were last fitted into, for leaving the month without a width at hand.
    @ObservationIgnored private(set) var trackWidth: CGFloat = 0

    let service: any MemoryService
    /// The hours of one calendar month, for the Month scale.
    public let month: TimelineMonth
    let referenceDate: Date
    let calendar = Calendar.current
    private let dayCount = 2
    private static let maxPrefetchDays = 365
    private var prefetchDays = 2
    private let neighbourOffsets = [1, -1, 2, -2, 3, -3]
    private var reachedHistoryStart = false
    private var isLoadingOlder = false
    private var trackEpoch = 0
    private var cachedImages: [Moment.ID: CGImage] = [:]
    private var cachedOrder: [Moment.ID] = []
    @ObservationIgnored private(set) var loadTask: Task<Void, Never>?
    @ObservationIgnored private var olderTask: Task<Void, Never>?
    @ObservationIgnored private var imageTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?

    public init(
        service: any MemoryService,
        now: Date = Date(),
        pointsPerFrame: CGFloat = TimelineMetrics.defaultPointsPerFrame
    ) {
        self.service = service
        month = TimelineMonth(service: service)
        referenceDate = now
        let range = TimelineMetrics.pointsPerFrameRange
        self.pointsPerFrame = min(max(pointsPerFrame, range.lowerBound), range.upperBound)
    }

    public var selectedFrame: TrackFrame? {
        track?.frame(at: selectedIndex)
    }

    public var selectedDate: Date {
        selectedFrame?.capturedAt ?? track?.range.upperBound ?? referenceDate
    }

    public var selectedSegment: TrackSegment? {
        track?.segment(atFrame: selectedIndex)
    }

    public var isEmpty: Bool {
        hasLoaded && (track?.frames.isEmpty ?? true)
    }

    public var canOpenMoment: Bool {
        selectedFrame != nil
    }

    public var canGoNow: Bool {
        guard let track, !track.frames.isEmpty else { return false }
        if referenceDate < track.range.lowerBound || referenceDate > track.range.upperBound {
            return true
        }
        return selectedIndex < track.frames.count - 1
    }

    public var selectedMoment: Moment? {
        guard let frame = selectedFrame, let segment = selectedSegment else { return nil }
        return Moment(
            id: frame.id, capturedAt: frame.capturedAt, app: segment.app,
            windowTitle: segment.title,
            url: segment.host.flatMap { URL(string: "https://\($0)") })
    }

    // MARK: Loading

    public func load() async {
        guard !hasLoaded else { return }
        do {
            let loaded = try await service.timelineTrack(in: historyRange(endingAt: referenceDate))
            guard !Task.isCancelled else { return }
            apply(loaded, selecting: referenceDate)
        } catch {
            guard !Task.isCancelled else { return }
            hasLoaded = true
        }
    }

    private func apply(_ loaded: TimelineTrack, selecting date: Date) {
        track = loaded
        trackEpoch += 1
        hasLoaded = true
        reachedHistoryStart = false
        prefetchDays = 2
        isLoadingOlder = false
        selectedIndex = loaded.nearestIndex(to: date) ?? 0
        scrollGeneration += 1
        image = nil
        updateImage(debounced: false)
    }

    private func historyRange(endingAt date: Date) -> ClosedRange<Date> {
        let dayStart = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: dayStart) ?? dayStart
        let end = max(date, start)
        return start...end
    }

    // MARK: Selection

    public func select(index: Int) {
        guard let track, !track.frames.isEmpty else { return }
        let clamped = min(max(index, 0), track.frames.count - 1)
        if clamped != selectedIndex {
            selectedIndex = clamped
            updateImage()
        }
        scrollGeneration += 1
    }

    /// A frame the user scrolled under the playhead. It does not move the track again.
    public func reportScrolledIndex(_ index: Int) {
        guard let track, !track.frames.isEmpty else { return }
        let clamped = min(max(index, 0), track.frames.count - 1)
        guard clamped != selectedIndex else { return }
        selectedIndex = clamped
        updateImage()
    }

    public func step(by delta: Int) {
        select(index: selectedIndex + delta)
    }

    /// Steps to the start of a chip the track shows, so a step never stops inside one chip.
    public func stepSegment(by delta: Int) {
        guard let track, let segment = selectedSegment else { return }
        let runs = track.chipRuns()
        guard let current = runs.firstIndex(where: { $0.segments.contains(segment.id) }),
            runs.indices.contains(current + delta)
        else { return }
        select(index: track.segments[runs[current + delta].segments.lowerBound].frames.lowerBound)
    }

    public func zoom(by factor: CGFloat, keeping index: Int) {
        guard factor > 0 else { return }
        let range = TimelineMetrics.pointsPerFrameRange
        let clamped = min(max(pointsPerFrame * factor, range.lowerBound), range.upperBound)
        guard abs(clamped - pointsPerFrame) > 0.001 else { return }
        pointsPerFrame = clamped
        activeScale = nil
        let target = min(max(index, 0), max(0, (track?.frames.count ?? 1) - 1))
        if target != selectedIndex {
            selectedIndex = target
            updateImage()
        }
        scrollGeneration += 1
    }

    /// Applies `initialScale` once, after the first track loads and the track width is known.
    public func applyInitialScale(trackWidth: CGFloat) {
        guard !appliedInitialScale, track != nil, trackWidth > 0 else { return }
        appliedInitialScale = true
        setScale(Self.initialScale, trackWidth: trackWidth)
    }

    /// Fits the frames around the playhead of one preset span into the track width. Month shows
    /// the days of the selected frame's month instead, pointing at its hour.
    public func setScale(_ scale: TimelineScale, trackWidth: CGFloat) {
        guard let span = scale.frameSpan else {
            activeScale = scale
            month.point(at: selectedDate)
            return
        }
        guard let track, trackWidth > 0 else { return }
        self.trackWidth = trackWidth
        let date = selectedDate
        let lower = date.addingTimeInterval(-span / 2)
        let upper = date.addingTimeInterval(span / 2)
        let count = track.frames.reduce(into: 0) { total, frame in
            if frame.capturedAt >= lower, frame.capturedAt <= upper { total += 1 }
        }
        let range = TimelineMetrics.pointsPerFrameRange
        let fitted = count > 0 ? trackWidth / CGFloat(count) : pointsPerFrame
        pointsPerFrame = min(max(fitted, range.lowerBound), range.upperBound)
        activeScale = scale
        scrollGeneration += 1
    }

    // MARK: Jumping

    public func jump(to date: Date) {
        isChoosingDate = false
        if activeScale == .month {
            pointMonth(at: date)
            return
        }
        if let track, date >= track.range.lowerBound, date <= track.range.upperBound,
            let index = track.nearestIndex(to: date)
        {
            select(index: index)
            return
        }
        loadAround(date)
    }

    public func jumpToToday() {
        jump(to: referenceDate)
    }

    public func jumpToYesterday() {
        let yesterday =
            calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        jump(to: yesterday)
    }

    public func goNow() {
        jump(to: referenceDate)
    }

    public func setChoosingDate(_ shown: Bool) {
        isChoosingDate = shown
    }

    private func loadAround(_ date: Date) {
        load(historyRange(endingAt: date), selecting: date)
    }

    /// Replaces the track with `range` and selects the frame nearest `date`. A later load
    /// cancels this one, including during `delay`.
    func load(_ range: ClosedRange<Date>, selecting date: Date, after delay: Duration = .zero) {
        loadTask?.cancel()
        olderTask?.cancel()
        isLoadingOlder = false
        prefetchDays = 2
        loadTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            do {
                let loaded = try await self.service.timelineTrack(in: range)
                guard !Task.isCancelled else { return }
                self.apply(loaded, selecting: date)
            } catch {
                guard !Task.isCancelled else { return }
                self.hasLoaded = true
            }
        }
    }

    // MARK: Older history

    public func prefetchIfNeeded(visibleLowerBound: Int) {
        guard visibleLowerBound <= TimelineMetrics.prefetchFrames, !isLoadingOlder,
            !reachedHistoryStart,
            let track, !track.frames.isEmpty, track.frames.indices.contains(selectedIndex)
        else { return }
        let epoch = trackEpoch
        let selectedID = track.frames[selectedIndex].id
        isLoadingOlder = true
        olderTask = Task { [weak self] in
            guard let self else { return }
            await self.loadOlder(epoch: epoch, selectedID: selectedID)
        }
    }

    /// Loads one older window, doubling it after each empty one.
    ///
    /// A weekend, a paused week, or an erased range leaves no frame in the first window,
    /// and that must not end history while older frames exist.
    private func loadOlder(epoch: Int, selectedID: Moment.ID) async {
        while !Task.isCancelled, trackEpoch == epoch {
            guard let lowerBound = track?.range.lowerBound,
                let olderStart = calendar.date(
                    byAdding: .day, value: -prefetchDays, to: lowerBound),
                olderStart < lowerBound
            else {
                isLoadingOlder = false
                return
            }
            do {
                let older = try await service.timelineTrack(in: olderStart...lowerBound)
                guard !Task.isCancelled, trackEpoch == epoch else { return }
                if older.frames.isEmpty {
                    guard prefetchDays < Self.maxPrefetchDays else {
                        isLoadingOlder = false
                        reachedHistoryStart = true
                        return
                    }
                    prefetchDays = min(prefetchDays * 2, Self.maxPrefetchDays)
                    continue
                }
                isLoadingOlder = false
                prefetchDays = 2
                mergeOlder(older, selectedID: selectedID)
                return
            } catch {
                guard !Task.isCancelled, trackEpoch == epoch else { return }
                isLoadingOlder = false
                return
            }
        }
    }

    private func mergeOlder(_ older: TimelineTrack, selectedID: Moment.ID) {
        guard let current = track else { return }
        let merged = current.prepending(older)
        track = merged
        if let index = merged.frames.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = index
        }
        scrollGeneration += 1
    }
}

// MARK: Images

extension TimelineModel {
    /// Loads the selected frame's image. Scrubbing waits a moment first, so passing frames are
    /// skipped; opening and jumping load at once.
    private func updateImage(debounced: Bool = true) {
        imageTask?.cancel()
        prefetchTask?.cancel()
        guard let track, let frame = track.frame(at: selectedIndex) else {
            image = nil
            return
        }
        let id = frame.id
        let epoch = trackEpoch
        if let cached = cachedImages[id] {
            image = cached
            prefetchNeighbours(around: selectedIndex, epoch: epoch)
            return
        }
        imageTask = Task { [weak self] in
            if debounced { try? await Task.sleep(for: TimelineMetrics.selectionImageDelay) }
            guard !Task.isCancelled, let self else { return }
            let loaded = try? await self.service.image(
                for: id, maxPixelSize: TimelineMetrics.imageMaxPixels)
            guard let loaded else { return }
            guard !Task.isCancelled, self.trackEpoch == epoch, self.selectedFrame?.id == id else {
                return
            }
            self.store(loaded, for: id)
            self.image = loaded
            self.prefetchNeighbours(around: self.selectedIndex, epoch: epoch)
        }
    }

    private func prefetchNeighbours(around index: Int, epoch: Int) {
        guard let track else { return }
        let missing = neighbourOffsets.compactMap { offset in
            track.frame(at: index + offset)
        }.filter { cachedImages[$0.id] == nil }
        guard !missing.isEmpty else { return }
        prefetchTask = Task { [weak self] in
            for frame in missing {
                try? await Task.sleep(for: TimelineMetrics.prefetchImageDelay)
                guard !Task.isCancelled, let self, self.trackEpoch == epoch else { return }
                guard
                    let loaded = try? await self.service.image(
                        for: frame.id, maxPixelSize: TimelineMetrics.imageMaxPixels)
                else { continue }
                guard !Task.isCancelled, self.trackEpoch == epoch else { return }
                self.store(loaded, for: frame.id)
            }
        }
    }

    private func store(_ image: CGImage, for id: Moment.ID) {
        cachedImages[id] = image
        cachedOrder.removeAll { $0 == id }
        cachedOrder.append(id)
        let capacity = TimelineMetrics.imageCacheRadius * 2 + 1
        while cachedOrder.count > capacity {
            cachedImages.removeValue(forKey: cachedOrder.removeFirst())
        }
    }
}
