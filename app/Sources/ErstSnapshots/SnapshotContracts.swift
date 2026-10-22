import CoreGraphics
import CoreText
import ErstModel
import ErstPreview
import ErstUI
import Foundation

/// Behavioral checks that can run with the Command Line Tools, without swift test.
@MainActor
enum SnapshotContracts {
    static func verify() async throws {
        try settingsDocuments()
        try await previewQueries()
        try await timelineTracks()
        try trackHeat()
        try prependSessions()
        try windowTitles()
        try ReadingBlocksContract.verify()
        try TrackRunsContract.verify()
        try MarkContract.verify()
        try OverlaySurfaceContract.verify()
        try await settingsActions()
        try await scrollDocumentMemory()
        try await TimelineOpenContract.verify(
            now: Calendar.current.date(bySettingHour: 17, minute: 42, second: 8, of: Date()) ?? Date())
        let font = CTFontCreateWithName("SchibstedGrotesk-Regular" as CFString, 13, nil)
        try require(
            (CTFontCopyFamilyName(font) as String) == "Schibsted Grotesk",
            "The bundled Schibsted Grotesk font must be registered."
        )
        print(
            "Contracts passed: settings JSON, filtered search, timeline track, track heat, prepend, "
                + "window titles, reading blocks, track chips, mark, overlay clicks, scroll memory, timeline opens on the newest frame, erase, agents, "
                + "debounced saves, fonts.")
    }

    private static func settingsDocuments() throws {
        let decoder = JSONDecoder()
        let missing = try decoder.decode(ErstSettings.self, from: Data("{}".utf8))
        try require(missing == .default, "Missing settings must keep the defaults.")
        let legacy = Data(
            """
            {"isRecording":false,"skipUnchangedFrames":false,"skipPrivateWindows":true,
             "skipPasswordFields":true,"pauseWhileSharingScreen":true,"encryptHistory":true,
             "agentContent":"textAndImages","askBeforeAgentRequest":true,"afterLighterCopy":"textOnly"}
            """.utf8
        )
        var expected = ErstSettings.default
        expected.isRecording = false
        try require(
            try decoder.decode(ErstSettings.self, from: legacy) == expected,
            "Removed keys must not break an older settings document."
        )
        var unlimited = ErstSettings.default
        unlimited.lighterCopyMonths = nil
        unlimited.storageLimitGigabytes = nil
        unlimited.agentHistoryDays = nil
        let encoded = try JSONEncoder().encode(unlimited)
        try require(
            try decoder.decode(ErstSettings.self, from: encoded) == unlimited,
            "Unlimited choices must survive a JSON round trip."
        )
        let choices: [(Int, Int, Int?, Int?, Int?)] = [
            (1, 3, 1, 5, 1), (2, 7, 3, 10, 7), (5, 14, 6, 20, 30), (10, 30, 12, 50, 90),
        ]
        for (capture, full, lighter, limit, history) in choices {
            var settings = ErstSettings.default
            settings.captureIntervalSeconds = capture
            settings.fullQualityDays = full
            settings.lighterCopyMonths = lighter
            settings.storageLimitGigabytes = limit
            settings.agentHistoryDays = history
            settings.afterLighterCopy = .deleteEverything
            let document = try JSONEncoder().encode(settings)
            try require(
                try decoder.decode(ErstSettings.self, from: document) == settings,
                "Every supported choice must survive a JSON round trip."
            )
        }
    }

    private static func previewQueries() async throws {
        let service = PreviewMemoryService()
        let hits = try await service.search(SearchQuery(text: "design system"), limit: 5000)
        guard let oldest = hits.last else { throw SnapshotError.noMoment }
        let query = SearchQuery(
            text: "design system", app: oldest.moment.app, range: oldest.firstSeen...oldest.lastSeen
        )
        let filtered = try await service.search(query, limit: 1)
        try require(filtered.first?.id == oldest.id, "Apply app and date filters before the result limit.")
        try require(try await service.search(query, limit: 0).isEmpty, "A zero limit must return no results.")
        let directory = service.dataDirectory.standardizedFileURL.path
        try require(directory.hasPrefix(URL.temporaryDirectory.path), "Preview storage must be temporary.")
        try await service.erase(oldest.firstSeen...oldest.lastSeen)
        try require(
            try await service.search(query, limit: 10).isEmpty, "Erased preview moments must disappear.")
        let remaining = try await service.search(SearchQuery(text: "design system"), limit: 1)
        try require(!remaining.isEmpty, "Erasing one visit must preserve unrelated history.")
        let empty = PreviewMemoryService(includesHistory: false)
        try require(
            try await empty.nearestMoment(to: Date()) == nil,
            "The empty dataset must have no moments."
        )
    }

    private static func timelineTracks() async throws {
        let anchor = Calendar.current.date(bySettingHour: 17, minute: 42, second: 8, of: Date()) ?? Date()
        let service = PreviewMemoryService(now: anchor)
        let start = Calendar.current.date(byAdding: .day, value: -2, to: anchor) ?? anchor
        let track = try await service.timelineTrack(in: start...anchor)
        try require(!track.frames.isEmpty, "The preview track must hold kept frames.")
        for frame in track.frames {
            try require(
                track.segments.indices.contains(frame.segment),
                "Every frame must point at one segment.")
            let segment = track.segments[frame.segment]
            try require(
                segment.frames.contains(track.frames.firstIndex { $0.id == frame.id } ?? -1),
                "A segment's frame range must contain its own frames.")
            try require(
                segment.range.contains(frame.capturedAt),
                "A segment's time range must contain its own frames.")
            try require((0...1).contains(frame.changeRatio), "A change ratio stays between 0 and 1.")
        }
        for (index, segment) in track.segments.enumerated() {
            try require(segment.id == index, "Segment ids must be their index in the track.")
            try require(
                segment.frames.lowerBound <= segment.frames.upperBound,
                "A segment's frame range must not be empty.")
            if index > 0 {
                try require(
                    segment.frames.lowerBound == track.segments[index - 1].frames.upperBound + 1,
                    "Segment frame ranges must be contiguous.")
            }
        }
        try require(
            track.segments.filter(\.startsSession).count >= 2,
            "Two local days must start at least two sessions.")
        try require(
            track.segments.contains { $0.title?.isEmpty == false },
            "A segment must carry the window title of its last frame.")
        try await prependedTrack(anchor: anchor)
        let empty = PreviewMemoryService(now: anchor, includesHistory: false)
        try require(
            try await empty.timelineTrack(in: start...anchor).frames.isEmpty,
            "The empty dataset must have no track frames.")
    }

    /// A quiet frame stays dark, and full changes close together climb to the top level.
    private static func trackHeat() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        func frame(_ seconds: TimeInterval, _ ratio: Double) -> TrackFrame {
            TrackFrame(
                id: Int64(seconds), capturedAt: base.addingTimeInterval(seconds), changeRatio: ratio,
                segment: 0)
        }
        // A quiet frame alone, a full change alone, seven full changes 10 s apart.
        let lone = TrackHeat.levels(for: [frame(0, 0.01), frame(600, 0.3)])
        try require(
            lone == [0, 1], "A quiet lone frame is level 0 and a lone full change is level 1.")
        let burst = TrackHeat.levels(for: (0..<7).map { frame(1_200 + Double($0) * 10, 0.3) })
        try require(burst[3] == 5, "Seven full changes inside one minute are level 5.")
    }

    /// An older chunk joins in front of the loaded one without breaking segment indexes.
    private static func prependedTrack(anchor: Date) async throws {
        let calendar = Calendar.current
        let boundary = calendar.startOfDay(for: anchor)
        guard let start = calendar.date(byAdding: .day, value: -2, to: boundary) else { return }
        let service = PreviewMemoryService(now: anchor)
        let older = try await service.timelineTrack(in: start...boundary)
        let newer = try await service.timelineTrack(in: boundary...anchor)
        try require(!older.frames.isEmpty && !newer.frames.isEmpty, "Both chunks must hold frames.")
        let merged = newer.prepending(older)
        try require(
            merged.frames.count == older.frames.count + newer.frames.count,
            "Prepending must keep every frame.")
        try require(
            merged.frames.map(\.capturedAt) == merged.frames.map(\.capturedAt).sorted(),
            "Prepending must keep frames in time order.")
        for segment in merged.segments {
            try require(
                merged.segments.indices.contains(segment.id) && merged.segments[segment.id] == segment,
                "Prepending must keep segment ids equal to their index.")
            for index in segment.frames {
                try require(
                    merged.frames.indices.contains(index) && merged.frames[index].segment == segment.id,
                    "A prepended segment must point at its own frames.")
            }
        }
    }

    /// A chunk boundary joins a visit only inside the session gap, whatever the engine marked.
    private static func prependSessions() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let safari = AppRef(bundleID: "com.apple.Safari", name: "Safari")
        let notes = AppRef(bundleID: "com.apple.Notes", name: "Notes")
        let older = chunk(app: safari, host: "design.example.com", start: base, count: 10)
        let adjacent = chunk(
            app: safari, host: "design.example.com", start: base.addingTimeInterval(15), count: 6)
        let joined = adjacent.prepending(older)
        try require(
            joined.segments.count == 1,
            "Adjacent chunks of one visit must join into one segment.")
        try require(joined.frames.count == 16, "A joined prepend must keep every frame.")
        try require(
            joined.segments[0].frames == 0...15,
            "The joined segment must cover both chunks in order.")
        let later = chunk(
            app: safari, host: "design.example.com",
            start: base.addingTimeInterval(9 + 11 * 60), count: 6)
        let apart = later.prepending(older)
        try require(
            apart.segments.count == 2, "Chunks 11 minutes apart must stay two segments.")
        try require(
            apart.segments[1].startsSession,
            "A chunk after the session gap must mark its first segment as a session start.")
        let switched = chunk(app: notes, host: nil, start: base.addingTimeInterval(15), count: 6)
        let bridged = switched.prepending(older)
        try require(bridged.segments.count == 2, "A new app must start a second segment.")
        try require(
            !bridged.segments[1].startsSession,
            "A chunk boundary inside the session gap must not paint a pause.")
    }

    /// A window title drops the app name that many apps append after a separator.
    private static func windowTitles() throws {
        let cases: [(title: String, app: String, expected: String?)] = [
            ("T3 Code (Beta)", "T3 Code (Beta)", nil),
            ("Inbox - Mail", "Mail", "Inbox"),
            ("Doc - Draft - Pages", "Pages", "Doc - Draft"),
            ("Mail", "Notes", "Mail"),
            ("  ", "Notes", nil),
            ("(4) I Raided With 0 Viewers \u{2013} Helium", "Helium", "(4) I Raided With 0 Viewers"),
            ("Draft \u{2014} Pages", "Pages", "Draft"),
            ("Note \u{00B7} Brain", "Brain", "Note"),
            ("Docs | Linear", "Linear", "Docs"),
        ]
        for (title, app, expected) in cases {
            try require(
                WindowTitle.clean(title, appName: app) == expected,
                "A window title must drop only the trailing app name: \(title)")
        }
    }

    /// A sidebar column reads before the content beside it and becomes a list of items, a wrapped
    /// sentence joins into one line, a line ending in a hyphen joins without a space (the hyphen
    /// stays, since it may belong to a compound), items on one row keep a gap, and a smaller line
    /// under a title stays its own line.
    private static func chunk(
        app: AppRef, host: String?, start: Date, count: Int
    ) -> TimelineTrack {
        let frames = (0..<count).map { offset in
            TrackFrame(
                id: Int64(start.timeIntervalSince1970) + Int64(offset),
                capturedAt: start.addingTimeInterval(TimeInterval(offset)),
                changeRatio: 0.1, segment: 0)
        }
        let end = start.addingTimeInterval(TimeInterval(count - 1))
        let segment = TrackSegment(
            id: 0, app: app, host: host, title: "Notes", frames: 0...(count - 1),
            range: start...end, startsSession: true)
        return TimelineTrack(range: start...end, frames: frames, segments: [segment])
    }

    /// Hosts the real scroller over 50,000 frames and prints the memory it holds.
    private static func scrollDocumentMemory() async throws {
        let frameCount = 50_000
        let pointsPerFrame: CGFloat = 24
        let viewport = CGSize(width: 1_140, height: 120)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let frames = (0..<frameCount).map { index in
            TrackFrame(
                id: Int64(index), capturedAt: base.addingTimeInterval(TimeInterval(index)),
                changeRatio: 0.1, segment: 0)
        }
        let end = base.addingTimeInterval(TimeInterval(frameCount - 1))
        let segment = TrackSegment(
            id: 0, app: AppRef(bundleID: "com.apple.Safari", name: "Safari"),
            host: "design.example.com", title: "Notes", frames: 0...(frameCount - 1),
            range: base...end, startsSession: true)
        let track = TimelineTrack(range: base...end, frames: frames, segments: [segment])
        guard
            let reading = await TimelineTrackMemoryProbe.measure(
                track: track, pointsPerFrame: pointsPerFrame, viewportSize: viewport)
        else { throw SnapshotError.contract("The memory probe must find the track scroller.") }
        try require(
            reading.documentWidth >= CGFloat(frameCount) * pointsPerFrame,
            "The long track document must be 50,000 frames wide.")
        let megabyte = 1_048_576.0
        print(
            String(
                format:
                    "Timeline scroll memory: %.1f MB before, %.1f MB after setup, %.1f MB after "
                    + "three scrolls (%.1f MB total growth, %.1f MB from scrolling), document %.0f pt.",
                Double(reading.beforeBytes) / megabyte,
                Double(reading.afterSetupBytes) / megabyte,
                Double(reading.afterScrollBytes) / megabyte,
                Double(reading.growthBytes) / megabyte,
                Double(reading.scrollGrowthBytes) / megabyte,
                reading.documentWidth))
    }

    private static func settingsActions() async throws {
        let service = PreviewMemoryService()
        let agents = PreviewAgentClientService()
        let model = SettingsModel(service: service, agents: agents)
        await model.load()
        model.binding(\.captureIntervalSeconds).wrappedValue = 5
        model.binding(\.captureIntervalSeconds).wrappedValue = 10
        try await Task.sleep(for: .milliseconds(400))
        try require(
            try await service.settings().captureIntervalSeconds == 10,
            "The debounced save must persist the final change."
        )
        try await agents.connect(.codex)
        try require(
            await agents.clients().first { $0.id == .codex }?.isConnected == true,
            "Connect must update the preview client."
        )
        try await agents.disconnect(.codex)
        try require(
            await agents.clients().first { $0.id == .codex }?.isConnected == false,
            "Disconnect must update the preview client."
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SnapshotError.contract(message) }
    }
}
