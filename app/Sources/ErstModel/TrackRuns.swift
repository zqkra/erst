import Foundation

/// Consecutive segments the timeline draws as one chip.
public struct TrackRun: Hashable, Sendable {
    /// The indexes in `TimelineTrack.segments` this run covers.
    public let segments: ClosedRange<Int>
    /// The segment the chip names: the one with the most frames of the app with the most time on
    /// screen in the run.
    public let lead: Int
    /// True when the run begins after a pause longer than the session gap.
    public let startsSession: Bool
}

extension TimelineTrack {
    /// Time on screen below which a stretch of one app is a glance: a pass through it while
    /// switching, a notification, a screenshot tool.
    public static let glanceSeconds: TimeInterval = 15

    /// Groups segments into the chips the timeline draws.
    ///
    /// Neighbours from the same app always share a chip, so moving between sites or windows of one
    /// app reads as one stretch of it. A glance, an app on screen for less than `glanceSeconds`,
    /// joins its neighbours: both of them when they belong to the same app, else the one before it,
    /// else the one after it. Time on screen runs from the stretch's first frame to the next
    /// stretch's first frame, because a switch of app always keeps a frame. It is never measured
    /// in frames: an app read quietly for ten minutes keeps few frames and is still not a glance.
    /// A pause between sessions is never crossed, and the last stretch, which may still be going,
    /// is never a glance.
    public func chipRuns() -> [TrackRun] {
        var stack: [Draft] = []
        for (index, segment) in segments.enumerated() {
            var run = Draft(segment, seconds: secondsOnScreen(index))
            // A glance joins the stretch before it; when that one is the same app as this run, the
            // same-app rule below then closes the gap around the glance.
            if let glance = stack.last, glance.isGlance, !run.startsSession {
                stack.removeLast()
                if !stack.isEmpty, !glance.startsSession {
                    stack[stack.count - 1].absorb(glance)
                } else {
                    run = glance.absorbing(run)
                }
            }
            if let last = stack.last, last.app == run.app, !run.startsSession {
                stack[stack.count - 1].absorb(run)
            } else {
                stack.append(run)
            }
        }
        return stack.map { $0.run(in: segments) }
    }

    /// From the segment's first frame to the next segment's, or forever when a pause or the end of
    /// the track follows it, since then nothing says when it left the screen.
    private func secondsOnScreen(_ index: Int) -> TimeInterval {
        let next = index + 1
        guard segments.indices.contains(next), !segments[next].startsSession else { return .infinity }
        return segments[next].range.lowerBound.timeIntervalSince(segments[index].range.lowerBound)
    }
}

/// A run while it is being built: its segments and each app's time on screen in it.
private struct Draft {
    var first: Int
    var last: Int
    var startsSession: Bool
    var secondsByApp: [String: TimeInterval]

    init(_ segment: TrackSegment, seconds: TimeInterval) {
        first = segment.id
        last = segment.id
        startsSession = segment.startsSession
        secondsByApp = [segment.app.bundleID: seconds]
    }

    var isGlance: Bool { secondsByApp.values.reduce(0, +) < TimelineTrack.glanceSeconds }

    /// The app with the most time on screen, the name a chip carries. Frames do not decide it: a
    /// quiet app keeps few. Ties go to the earlier bundle ID so dictionary order does not matter.
    var app: String {
        secondsByApp.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key > rhs.key
        }?.key ?? ""
    }

    mutating func absorb(_ other: Draft) {
        first = min(first, other.first)
        last = max(last, other.last)
        startsSession = first == other.first ? other.startsSession : startsSession
        secondsByApp.merge(other.secondsByApp, uniquingKeysWith: +)
    }

    func absorbing(_ other: Draft) -> Draft {
        var merged = self
        merged.absorb(other)
        return merged
    }

    func run(in segments: [TrackSegment]) -> TrackRun {
        let app = app
        let lead =
            (first...last)
            .filter { segments[$0].app.bundleID == app }
            .max { segments[$0].frames.count < segments[$1].frames.count } ?? first
        return TrackRun(segments: first...last, lead: lead, startsSession: startsSession)
    }
}
