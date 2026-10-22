import ErstModel
import Foundation

/// Checks how the timeline groups segments into chips.
enum TrackRunsContract {
    private static let helium = AppRef(bundleID: "net.imput.helium", name: "Helium")
    private static let code = AppRef(bundleID: "com.t3.code", name: "T3 Code")
    private static let zed = AppRef(bundleID: "dev.zed.Zed", name: "Zed")
    /// Longer than the session gap, so a segment that starts a session follows a real pause.
    private static let pauseSeconds: TimeInterval = 20 * 60

    static func verify() throws {
        try expect(
            [stretch(helium, 20, 300, "x.com"), stretch(helium, 20, 300, "youtube.com")],
            runs: [(0...1, 0, false)],
            "Sites of one app must share one chip")
        try expect(
            [stretch(helium, 30, 300), stretch(code, 2, 5), stretch(helium, 30, 300)],
            runs: [(0...2, 0, false)],
            "A glance at another app between two stretches of one app must not cut the chip")
        try expect(
            [stretch(helium, 30, 300), stretch(code, 3, 600), stretch(helium, 30, 300)],
            runs: [(0...0, 0, false), (1...1, 1, false), (2...2, 2, false)],
            "Ten quiet minutes in an app keep few frames and must still get a chip")
        try expect(
            [stretch(helium, 30, 300), stretch(code, 2, 5), stretch(zed, 30, 300)],
            runs: [(0...1, 0, false), (2...2, 2, false)],
            "A glance between two apps must join the one before it")
        try expect(
            [stretch(code, 2, 5), stretch(helium, 30, 300)],
            runs: [(0...1, 1, false)],
            "A glance first on the track must join the one after it and take its name")
        try expect(
            [stretch(helium, 30, 300), stretch(code, 2, 5, startsSession: true), stretch(helium, 30, 300)],
            runs: [(0...0, 0, false), (1...2, 2, true)],
            "A pause between sessions must never be crossed")
        try expect(
            [stretch(helium, 30, 300), stretch(code, 1, 2)],
            runs: [(0...0, 0, false), (1...1, 1, false)],
            "The last stretch may still be going and must never be a glance")
    }

    private struct Stretch {
        let app: AppRef
        let frames: Int
        let seconds: TimeInterval
        let host: String?
        let startsSession: Bool
    }

    private static func stretch(
        _ app: AppRef, _ frames: Int, _ seconds: TimeInterval, _ host: String? = nil,
        startsSession: Bool = false
    ) -> Stretch {
        Stretch(app: app, frames: frames, seconds: seconds, host: host, startsSession: startsSession)
    }

    private static func expect(
        _ stretches: [Stretch], runs expected: [(ClosedRange<Int>, Int, Bool)], _ message: String
    ) throws {
        let runs = track(stretches).chipRuns()
        let matches =
            runs.count == expected.count
            && zip(runs, expected).allSatisfy { run, want in
                run.segments == want.0 && run.lead == want.1 && run.startsSession == want.2
            }
        if !matches { throw SnapshotError.contract("\(message): \(runs)") }
    }

    /// Frames spread evenly over each stretch's time on screen, one stretch after another.
    private static func track(_ stretches: [Stretch]) -> TimelineTrack {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        var frames: [TrackFrame] = []
        var segments: [TrackSegment] = []
        for (index, stretch) in stretches.enumerated() {
            if stretch.startsSession { clock = clock.addingTimeInterval(pauseSeconds) }
            let first = frames.count
            let step = stretch.seconds / Double(stretch.frames)
            for offset in 0..<stretch.frames {
                frames.append(
                    TrackFrame(
                        id: Int64(frames.count), capturedAt: clock.addingTimeInterval(step * Double(offset)),
                        changeRatio: 0, segment: index))
            }
            segments.append(
                TrackSegment(
                    id: index, app: stretch.app, host: stretch.host, frames: first...(frames.count - 1),
                    range: frames[first].capturedAt...frames[frames.count - 1].capturedAt,
                    startsSession: stretch.startsSession))
            clock = clock.addingTimeInterval(stretch.seconds)
        }
        let start = frames.first?.capturedAt ?? clock
        return TimelineTrack(
            range: start...(frames.last?.capturedAt ?? start), frames: frames, segments: segments)
    }
}
