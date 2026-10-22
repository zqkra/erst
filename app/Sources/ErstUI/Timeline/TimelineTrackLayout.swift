import CoreGraphics
import ErstModel
import Foundation

/// The x position of every frame and chip at one zoom level.
///
/// Frame x positions are in track coordinates: zero is the left edge of the first
/// frame and the content ends at `contentWidth`. Segments are drawn as chips grouped by
/// `TimelineTrack.chipRuns`, so one app's stretch is one continuous chip and a glance at another
/// app does not cut it. A chip gap separates one chip from the next, and a wider gap holds the
/// pause chip between sessions.
struct TimelineTrackLayout: Sendable {
    struct ChipBounds: Sendable {
        let run: TrackRun
        let minX: CGFloat
        let maxX: CGFloat
        let gapWidth: CGFloat
    }

    struct HourLabel: Sendable {
        let x: CGFloat
        let text: String
    }

    let frameCenters: [CGFloat]
    let chips: [ChipBounds]
    let hourLabels: [HourLabel]
    let contentWidth: CGFloat
    let pointsPerFrame: CGFloat

    static let empty = TimelineTrackLayout()

    private init() {
        frameCenters = []
        chips = []
        hourLabels = []
        contentWidth = 0
        pointsPerFrame = TimelineMetrics.defaultPointsPerFrame
    }

    @MainActor
    init(track: TimelineTrack, pointsPerFrame: CGFloat) {
        var centers = [CGFloat](repeating: 0, count: track.frames.count)
        let runs = track.chipRuns()
        var bounds: [ChipBounds] = []
        bounds.reserveCapacity(runs.count)
        var cursor: CGFloat = 0
        for (index, run) in runs.enumerated() {
            let gap =
                index == 0
                ? 0 : (run.startsSession ? TimelineMetrics.sessionGap : TimelineMetrics.chipGap)
            cursor += gap
            let start = cursor
            for segmentIndex in run.segments where track.segments.indices.contains(segmentIndex) {
                for frameIndex in track.segments[segmentIndex].frames {
                    guard centers.indices.contains(frameIndex) else { continue }
                    centers[frameIndex] = cursor + pointsPerFrame / 2
                    cursor += pointsPerFrame
                }
            }
            bounds.append(ChipBounds(run: run, minX: start, maxX: cursor, gapWidth: gap))
        }
        frameCenters = centers
        chips = bounds
        hourLabels = TimelineTrackLayout.hourLabels(track: track, centers: centers)
        contentWidth = cursor
        self.pointsPerFrame = pointsPerFrame
    }

    var isEmpty: Bool { frameCenters.isEmpty }

    /// The frame whose center is closest to an x position.
    func index(atX x: CGFloat) -> Int {
        guard !frameCenters.isEmpty else { return 0 }
        var low = 0
        var high = frameCenters.count - 1
        while low < high {
            let middle = (low + high) / 2
            if frameCenters[middle] < x {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0 else { return 0 }
        let before = low - 1
        return abs(frameCenters[before] - x) <= abs(frameCenters[low] - x) ? before : low
    }

    /// The frames whose centers fall inside a horizontal range, plus their neighbours.
    func frameIndices(minX: CGFloat, maxX: CGFloat) -> ClosedRange<Int>? {
        guard !frameCenters.isEmpty else { return nil }
        let lower = index(atX: minX - pointsPerFrame)
        let upper = index(atX: maxX + pointsPerFrame)
        return min(lower, upper)...max(lower, upper)
    }

    /// The pause chip that sits in the gap before a chip that starts a session.
    func sessionChipX(forChip index: Int) -> CGFloat? {
        guard chips.indices.contains(index) else { return nil }
        let bounds = chips[index]
        guard bounds.run.startsSession, bounds.gapWidth > 0 else { return nil }
        return bounds.minX - bounds.gapWidth + TimelineMetrics.chipGap
    }

    @MainActor
    private static func hourLabels(track: TimelineTrack, centers: [CGFloat]) -> [HourLabel] {
        guard let first = track.frames.first else { return [] }
        let calendar = Calendar.current
        var hourInterval = calendar.dateInterval(of: .hour, for: first.capturedAt)
        var labels: [HourLabel] = []
        var lastLabelX = -CGFloat.infinity
        for (index, frame) in track.frames.enumerated() {
            guard centers.indices.contains(index) else { continue }
            guard let end = hourInterval?.end, frame.capturedAt >= end else { continue }
            hourInterval = calendar.dateInterval(of: .hour, for: frame.capturedAt)
            let x = centers[index]
            guard x - lastLabelX >= TimelineMetrics.hourLabelMinimumSpacing else { continue }
            let hour = calendar.component(.hour, from: frame.capturedAt)
            labels.append(HourLabel(x: x, text: TimelineFormat.hourText(hour)))
            lastLabelX = x
        }
        return labels
    }
}
