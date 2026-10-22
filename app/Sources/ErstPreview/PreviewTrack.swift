import ErstModel
import Foundation

extension PreviewDataset {
    /// Builds the frame-indexed track the timeline draws, grouped the way the engine groups it.
    ///
    /// A frame joins the open segment while its app, and its site for a browser, stays the
    /// same and the pause since the previous frame is at most the session gap. A longer
    /// pause starts a new segment and marks it as a session start.
    func track(in range: ClosedRange<Date>) -> TimelineTrack {
        let records =
            moments
            .filter { $0.moment.capturedAt >= range.lowerBound && $0.moment.capturedAt < range.upperBound }
            .sorted { $0.moment.capturedAt < $1.moment.capturedAt }
        var frames: [TrackFrame] = []
        var segments: [TrackSegment] = []
        var open: OpenSegment?
        var previousDate: Date?

        func closeOpenSegment() {
            guard let segment = open, let last = segment.lastDate else {
                open = nil
                return
            }
            segments.append(
                TrackSegment(
                    id: segments.count,
                    app: segment.app,
                    host: segment.host,
                    title: segment.lastTitle,
                    frames: segment.firstFrame...(frames.count - 1),
                    range: segment.firstDate...last,
                    startsSession: segment.startsSession))
            open = nil
        }

        for record in records {
            let host = PreviewSiteHost.host(record.moment.url)
            let pause = previousDate.map { record.moment.capturedAt.timeIntervalSince($0) } ?? .infinity
            let startsSession = pause > TimelineTrack.sessionGapSeconds
            let keyChanged = open?.app != record.moment.app || open?.host != host
            if open == nil || keyChanged || startsSession {
                closeOpenSegment()
                open = OpenSegment(
                    app: record.moment.app, host: host, firstFrame: frames.count,
                    firstDate: record.moment.capturedAt, lastDate: nil,
                    lastTitle: record.moment.windowTitle, startsSession: startsSession)
            }
            let startsSegment = open?.firstFrame == frames.count
            frames.append(
                TrackFrame(
                    id: record.moment.id,
                    capturedAt: record.moment.capturedAt,
                    changeRatio: PreviewTrackRules.changeRatio(
                        seed: record.moment.id, index: frames.count, startsSegment: startsSegment),
                    segment: segments.count))
            open?.lastDate = record.moment.capturedAt
            open?.lastTitle = record.moment.windowTitle
            previousDate = record.moment.capturedAt
        }
        closeOpenSegment()
        return TimelineTrack(range: range, frames: frames, segments: segments)
    }
}

private struct OpenSegment {
    let app: AppRef
    let host: String?
    let firstFrame: Int
    let firstDate: Date
    var lastDate: Date?
    var lastTitle: String?
    let startsSession: Bool
}

private enum PreviewTrackRules {
    static let segmentStartRatio = 0.28
    static let baseRatio = 0.02
    static let waveRatio = 0.09
    static let rippleRatio = 0.04

    /// A deterministic change ratio so the heat texture reads like the real recording.
    static func changeRatio(seed: Moment.ID, index: Int, startsSegment: Bool) -> Double {
        guard !startsSegment else { return segmentStartRatio }
        let phase = Double(abs(seed % 997)) / 997
        let wave = (sin(Double(index) * 0.9 + phase * 6.283) + 1) / 2
        let ripple = (sin(Double(index) * 2.6 + phase * 3.1) + 1) / 2
        return baseRatio + waveRatio * wave + rippleRatio * ripple
    }
}
