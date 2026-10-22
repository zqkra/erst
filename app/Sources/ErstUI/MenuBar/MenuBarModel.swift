import Combine
import ErstModel
import Foundation
import Observation

/// State for the menu bar window.
@MainActor
@Observable
// ObservableObject supports StateObject ownership with the Command Line Tools SDK.
public final class MenuBarModel: ObservableObject {
    public private(set) var summary: TodaySummary?
    public private(set) var status: RecorderStatus = .recording
    /// The row under the pointer or chosen with the arrow keys. One highlight, as in a menu.
    private(set) var highlighted: MenuBarAction?

    private let service: any MemoryService
    private var hasLoaded = false
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    public init(service: any MemoryService) {
        self.service = service
    }

    deinit {
        statusTask?.cancel()
    }

    /// Whether the recorder's state needs a line above the numbers: anything but normal recording.
    var showsStatus: Bool {
        if case .recording = status { return false }
        return true
    }

    /// Paused for a while or switched off in Settings. A missing permission is not a pause:
    /// resuming would not bring frames back.
    var isPaused: Bool {
        switch status {
        case .paused, .stopped: true
        case .recording, .needsPermission: false
        }
    }

    public func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        statusTask = Task { [weak self, service] in
            for await status in service.status {
                guard !Task.isCancelled else { return }
                self?.status = status
            }
        }
        summary = try? await service.todaySummary()
    }

    /// The pointer takes the highlight on entry and drops it on exit, unless another row has it.
    func hover(_ action: MenuBarAction, inside: Bool) {
        if inside {
            highlighted = action
        } else if highlighted == action {
            highlighted = nil
        }
    }

    /// Down from nothing starts at the top and up starts at the bottom; both wrap, as menus do.
    func moveHighlight(by step: Int, update: String?) {
        let all = MenuBarAction.rows(isPaused: isPaused, update: update)
        guard let current = highlighted, let index = all.firstIndex(of: current) else {
            highlighted = step > 0 ? all.first : all.last
            return
        }
        highlighted = all[(index + step + all.count) % all.count]
    }
}
