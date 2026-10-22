import AppKit
import Combine
import CoreGraphics
import ErstModel
import Foundation
import Observation

/// State for one moment and the moments around it.
@MainActor
@Observable
public final class MomentModel: ObservableObject {
    // ObservableObject lets StateObject own this model without the Xcode-only State macro.
    public private(set) var currentMoment: Moment
    public private(set) var detail: MomentDetail?
    public private(set) var image: CGImage?
    public private(set) var neighborImages: [Int64: CGImage] = [:]
    public var reminderPickerPresented = false
    public var reminderDate = Date().addingTimeInterval(defaultReminderOffsetSeconds)
    public let highlightedTerms: [String]
    /// Whether the text fills the inspector, with the title and details folded away.
    public private(set) var isTextExpanded = false

    /// The lines that hold a search term, for highlighter marks on the frame.
    public var matchedBoxes: [CGRect] {
        guard !highlightedTerms.isEmpty, let lines = detail?.lines else { return [] }
        return lines.filter { TermHighlight.matches($0.text, terms: highlightedTerms) }.map(\.box)
    }

    private let service: any MemoryService
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private static let defaultReminderOffsetSeconds: TimeInterval = 3600
    private let imageMaxSizePixels = 1800
    private let neighborImageMaxSizePixels = 260
    private let laterTodayOffsetSeconds: TimeInterval = 10_800
    private let morningHour = 9
    private let tomorrowOffsetDays = 1
    private let nextWeekDays = 7

    public init(service: any MemoryService, moment: Moment, highlightedTerms: [String] = []) {
        self.service = service
        currentMoment = moment
        self.highlightedTerms = highlightedTerms
    }

    public var previousMoment: Moment? {
        detail?.neighbors
            .filter { $0.capturedAt < currentMoment.capturedAt }
            .max { $0.capturedAt < $1.capturedAt }
    }

    public var nextMoment: Moment? {
        detail?.neighbors
            .filter { $0.capturedAt > currentMoment.capturedAt }
            .min { $0.capturedAt < $1.capturedAt }
    }

    public var onScreenText: String {
        guard let range = detail?.onScreen else { return "Not available" }
        return "\(ErstFormat.shortClock(range.lowerBound)) to \(ErstFormat.shortClock(range.upperBound))"
    }

    public var lastOpenedText: String {
        guard let date = detail?.lastOpened else { return "Never" }
        return ErstFormat.relativeDay(date)
    }

    public var hostText: String {
        currentMoment.url?.host() ?? currentMoment.app.name
    }

    public var primaryActionTitle: String {
        currentMoment.url == nil ? "Open in \(currentMoment.app.name)" : "Open page"
    }

    public func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await fetch(moment: currentMoment)
    }

    public func select(_ moment: Moment) {
        guard moment.id != currentMoment.id else { return }
        currentMoment = moment
        detail = nil
        image = neighborImages[moment.id]
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.fetch(moment: moment)
        }
    }

    public func goPrevious() {
        guard let moment = previousMoment else { return }
        select(moment)
    }

    public func goNext() {
        guard let moment = nextMoment else { return }
        select(moment)
    }

    public func cancelLoading() {
        loadTask?.cancel()
        hasLoaded = false
    }

    public func toggleTextExpanded() {
        isTextExpanded.toggle()
    }

    public func copyText() {
        let text = detail?.lines.inReadingOrder.map(\.text).joined(separator: "\n") ?? ""
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func openPage() {
        if let url = currentMoment.url {
            NSWorkspace.shared.open(url)
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: currentMoment.app.bundleID)
        else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    public func remindLaterToday() {
        remind(at: Date().addingTimeInterval(laterTodayOffsetSeconds))
    }

    public func remindTomorrow() {
        remind(at: morning(daysFromToday: tomorrowOffsetDays))
    }

    public func remindNextWeek() {
        remind(at: morning(daysFromToday: nextWeekDays))
    }

    public func remind(at date: Date) {
        Task { [service, currentMoment] in
            try? await service.addReminder(
                for: currentMoment.id,
                at: date,
                note: currentMoment.windowTitle ?? "Moment"
            )
        }
        reminderPickerPresented = false
    }

    private func fetch(moment: Moment) async {
        if let detail = try? await service.moment(id: moment.id) {
            guard !Task.isCancelled, currentMoment.id == moment.id else { return }
            self.detail = detail
            currentMoment = detail.moment
            let visibleIDs = Set(detail.neighbors.map(\.id) + [moment.id])
            neighborImages = neighborImages.filter { visibleIDs.contains($0.key) }
        }
        guard !Task.isCancelled, currentMoment.id == moment.id else { return }
        if let loaded = try? await service.image(for: moment.id, maxPixelSize: imageMaxSizePixels) {
            guard !Task.isCancelled, currentMoment.id == moment.id else { return }
            image = loaded
            neighborImages[moment.id] = loaded
        }
        await loadNeighbors(for: moment.id)
    }

    private func loadNeighbors(for momentID: Moment.ID) async {
        guard let neighbors = detail?.neighbors else { return }
        for neighbor in neighbors {
            guard !Task.isCancelled, currentMoment.id == momentID else { return }
            guard neighborImages[neighbor.id] == nil else { continue }
            if let image = try? await service.image(
                for: neighbor.id,
                maxPixelSize: neighborImageMaxSizePixels
            ) {
                guard !Task.isCancelled, currentMoment.id == momentID else { return }
                neighborImages[neighbor.id] = image
            }
        }
    }

    private func morning(daysFromToday: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()
        return calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: day) ?? day
    }
}
