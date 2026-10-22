import Foundation

/// One kept frame on the scrubber, with the segment it belongs to.
public struct TrackFrame: Hashable, Sendable {
    public let id: Moment.ID
    public let capturedAt: Date
    /// The share of the screen that changed since the previous kept frame, `0.0...1.0`.
    public let changeRatio: Double
    /// The index in `TimelineTrack.segments` that holds this frame.
    public let segment: Int

    public init(id: Moment.ID, capturedAt: Date, changeRatio: Double, segment: Int) {
        self.id = id
        self.capturedAt = capturedAt
        self.changeRatio = changeRatio
        self.segment = segment
    }
}

/// Consecutive frames from one app, and one website when the app was a browser.
public struct TrackSegment: Hashable, Identifiable, Sendable {
    /// The index in `TimelineTrack.segments`.
    public let id: Int
    public let app: AppRef
    public let host: String?
    /// Window title of the segment's last frame, trimmed, `nil` when it had none.
    public let title: String?
    /// The indexes in `TimelineTrack.frames` this segment covers.
    public let frames: ClosedRange<Int>
    public let range: ClosedRange<Date>
    /// True when the segment begins after a pause longer than the session gap.
    public let startsSession: Bool

    public init(
        id: Int,
        app: AppRef,
        host: String?,
        title: String? = nil,
        frames: ClosedRange<Int>,
        range: ClosedRange<Date>,
        startsSession: Bool
    ) {
        self.id = id
        self.app = app
        self.host = host
        self.title = title
        self.frames = frames
        self.range = range
        self.startsSession = startsSession
    }

    /// The line a timeline chip shows after the app name.
    public var detail: String? {
        if let host, !host.isEmpty { return host }
        return WindowTitle.clean(title, appName: app.name)
    }
}

/// Every frame and app segment inside one loaded range, ordered by capture time.
public struct TimelineTrack: Hashable, Sendable {
    public let range: ClosedRange<Date>
    public let frames: [TrackFrame]
    public let segments: [TrackSegment]
    /// The heat level of each frame, `0...5`, aligned with `frames`.
    public let heatLevels: [UInt8]

    public init(range: ClosedRange<Date>, frames: [TrackFrame], segments: [TrackSegment]) {
        self.range = range
        self.frames = frames
        self.segments = segments
        heatLevels = TrackHeat.levels(for: frames)
    }

    public var isEmpty: Bool { frames.isEmpty }

    /// The index of the frame captured closest to the date, if the track has any.
    public func nearestIndex(to date: Date) -> Int? {
        guard !frames.isEmpty else { return nil }
        var low = 0
        var high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if frames[middle].capturedAt < date {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let after = min(low, frames.count - 1)
        let before = max(0, low - 1)
        let beforeDistance = abs(frames[before].capturedAt.timeIntervalSince(date))
        let afterDistance = abs(frames[after].capturedAt.timeIntervalSince(date))
        return beforeDistance <= afterDistance ? before : after
    }

    public func frame(at index: Int) -> TrackFrame? {
        frames.indices.contains(index) ? frames[index] : nil
    }

    /// The segment that holds the frame at the index.
    public func segment(atFrame index: Int) -> TrackSegment? {
        guard let frame = frame(at: index), segments.indices.contains(frame.segment) else { return nil }
        return segments[frame.segment]
    }

    /// Joins an older, adjacent track in front of this one and keeps segment indexes valid.
    ///
    /// A visit that crosses the chunk boundary stays one segment when the gap between the
    /// chunks is within the session gap and the app and site did not change.
    public func prepending(_ older: TimelineTrack) -> TimelineTrack {
        guard !older.frames.isEmpty else { return self }
        guard !frames.isEmpty else { return older }
        var mergedFrames = older.frames
        var mergedSegments = older.segments
        guard let olderLast = older.segments.last, let currentFirst = segments.first else {
            return self
        }
        let gap = currentFirst.range.lowerBound.timeIntervalSince(olderLast.range.upperBound)
        let joins =
            gap >= 0 && gap <= Self.sessionGapSeconds
            && olderLast.app == currentFirst.app && olderLast.host == currentFirst.host
        let bridgesSessionGap = !joins && gap <= Self.sessionGapSeconds
        let shift = joins ? older.segments.count - 1 : older.segments.count
        let frameShift = older.frames.count
        for frame in frames {
            let segment = joins && frame.segment == currentFirst.id ? olderLast.id : frame.segment + shift
            mergedFrames.append(
                TrackFrame(
                    id: frame.id, capturedAt: frame.capturedAt, changeRatio: frame.changeRatio,
                    segment: segment))
        }
        if joins {
            let extended = TrackSegment(
                id: olderLast.id,
                app: olderLast.app,
                host: olderLast.host,
                title: currentFirst.title ?? olderLast.title,
                frames: olderLast.frames.lowerBound...(older.frames.count + currentFirst.frames.count - 1),
                range: olderLast.range
                    .lowerBound...max(olderLast.range.upperBound, currentFirst.range.upperBound),
                startsSession: olderLast.startsSession
            )
            mergedSegments[olderLast.id] = extended
            mergedSegments += segments.dropFirst().map {
                $0.shifted(segments: shift, frames: frameShift)
            }
        } else {
            mergedSegments += segments.map {
                $0.shifted(
                    segments: shift, frames: frameShift,
                    clearingSessionStart: bridgesSessionGap && $0.id == currentFirst.id)
            }
        }
        return TimelineTrack(
            range: older.range.lowerBound...range.upperBound,
            frames: mergedFrames,
            segments: mergedSegments
        )
    }
}

extension TimelineTrack {
    /// A pause longer than this starts a new session, as `SESSION_GAP_MS` does in `erst-core::track`.
    public static let sessionGapSeconds: TimeInterval = 600
}

extension TrackSegment {
    fileprivate func shifted(
        segments: Int, frames frameShift: Int, clearingSessionStart: Bool = false
    ) -> TrackSegment {
        TrackSegment(
            id: id + segments,
            app: app,
            host: host,
            title: title,
            frames: (frames.lowerBound + frameShift)...(frames.upperBound + frameShift),
            range: range,
            startsSession: clearingSessionStart ? false : startsSession
        )
    }
}
