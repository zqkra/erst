import Combine
import CoreGraphics
import ErstModel
import Foundation
import Observation

/// State for searching every line kept on screen.
@MainActor
@Observable
public final class SearchModel: ObservableObject {
    // ObservableObject lets StateObject own this model without the Xcode-only State macro.
    public static let resultLimit = 60
    public static let searchDebounceMilliseconds = 150
    public static let resultColumnCount = 3
    /// Recent visits shown before anything is typed.
    public static let recentLimit = 12

    public var query: String {
        didSet { if query != oldValue { clearResults() } }
    }
    public var appFilter: AppRef? {
        didSet { if appFilter != oldValue { clearResults() } }
    }
    public var timeFilter: SearchTimeFilter = .anyTime {
        didSet { if timeFilter != oldValue { clearResults() } }
    }
    public private(set) var appChoices: [AppRef] = []
    public private(set) var hits: [SearchHit] = []
    /// The newest moment of each recent visit, shown while the query is empty.
    public private(set) var recent: [SearchHit] = []
    public private(set) var selectedHitID: Int64?
    /// The card under the pointer, which gets a lighter platter than the selected one.
    public private(set) var hoveredHitID: Int64?
    public private(set) var images: [Moment.ID: CGImage] = [:]
    public private(set) var hasSearched = false

    @ObservationIgnored let keyboard = SearchKeyMonitor()
    private let service: any MemoryService
    private var hasLoadedFilters = false
    private let filterHistoryDays = 7
    private let thumbnailMaxSizePixels = 720
    private let recentWindowSeconds: TimeInterval = 24 * 60 * 60

    public init(service: any MemoryService, query: String = "") {
        self.service = service
        self.query = query
    }

    public var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var searchKey: String {
        "\(query)|\(appFilter?.bundleID ?? "")|\(timeFilter.rawValue)"
    }

    public var highlightTerms: [String] {
        trimmedQuery.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .filter { !$0.isEmpty }
    }

    /// What the grid shows: search results once something is typed, recent visits before.
    public var displayedHits: [SearchHit] {
        trimmedQuery.isEmpty ? recent : hits
    }

    public var selectedHit: SearchHit? {
        guard let selectedHitID else { return nil }
        return displayedHits.first { $0.id == selectedHitID }
    }

    public func loadFilters() async {
        guard !hasLoadedFilters else { return }
        hasLoadedFilters = true
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -filterHistoryDays, to: end),
            let report = try? await service.activity(in: start...end)
        else { return }
        guard !Task.isCancelled else { return }
        var bundleIDs: Set<String> = []
        appChoices = report.apps.map(\.app).filter { bundleIDs.insert($0.bundleID).inserted }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public func search() async {
        guard !trimmedQuery.isEmpty else {
            clearResults()
            return
        }
        hasSearched = false
        let key = searchKey
        let request = SearchQuery(text: trimmedQuery, app: appFilter, range: timeFilter.range())
        do {
            let results = try await service.search(request, limit: Self.resultLimit)
            guard !Task.isCancelled, key == searchKey else { return }
            hits = results
            selectedHitID = results.first?.id
        } catch {
            guard !Task.isCancelled, key == searchKey else { return }
            hits = []
            selectedHitID = nil
        }
        hasSearched = true
    }

    /// Loads the newest moment of each visit in the time filter, or the last 24 hours, newest
    /// first, keeping only the app filter's app when one is set.
    public func loadRecent() async {
        let end = Date()
        let window = timeFilter.range() ?? end.addingTimeInterval(-recentWindowSeconds)...end
        let key = searchKey
        guard let track = try? await service.timelineTrack(in: window) else { return }
        guard !Task.isCancelled, key == searchKey else { return }
        var visits: [SearchHit] = []
        for segment in track.segments.reversed() where appFilter.map({ $0 == segment.app }) ?? true {
            guard let frame = track.frame(at: segment.frames.upperBound) else { continue }
            let moment = Moment(
                id: frame.id, capturedAt: frame.capturedAt, app: segment.app,
                windowTitle: segment.title,
                url: segment.host.flatMap { URL(string: "https://\($0)") })
            visits.append(
                SearchHit(
                    moment: moment, matchedLines: [],
                    firstSeen: segment.range.lowerBound, lastSeen: segment.range.upperBound))
            if visits.count == Self.recentLimit { break }
        }
        recent = visits
        selectedHitID = visits.first?.id
    }

    public func clearQuery() {
        query = ""
        clearResults()
    }

    public func select(_ hit: SearchHit) {
        selectedHitID = hit.id
    }

    func hover(_ hit: SearchHit, inside: Bool) {
        if inside {
            hoveredHitID = hit.id
        } else if hoveredHitID == hit.id {
            hoveredHitID = nil
        }
    }

    public func moveSelection(by offset: Int) {
        let shown = displayedHits
        guard !shown.isEmpty else { return }
        let current = shown.firstIndex { $0.id == selectedHitID } ?? 0
        let next = min(max(current + offset, 0), shown.count - 1)
        selectedHitID = shown[next].id
    }

    public func loadThumbnail(for hit: SearchHit) async {
        guard !Task.isCancelled, images[hit.moment.id] == nil else { return }
        guard
            let image = try? await service.image(for: hit.moment.id, maxPixelSize: thumbnailMaxSizePixels),
            !Task.isCancelled,
            displayedHits.contains(where: { $0.id == hit.id })
        else { return }
        images[hit.moment.id] = image
    }

    private func clearResults() {
        hits = []
        selectedHitID = nil
        images = [:]
        hasSearched = false
    }
}
