import ErstModel
import Foundation

/// One surface in the overlay chain.
///
/// Search and Timeline are roots. A Moment is pushed on top of the root it was opened
/// from, so Escape can return to that root instead of closing everything.
enum OverlaySurface {
    case search
    case timeline(at: Date)
    case moment(Moment, terms: [String])

    var isSearch: Bool {
        if case .search = self { return true }
        return false
    }

    var isTimeline: Bool {
        if case .timeline = self { return true }
        return false
    }

    var isMoment: Bool {
        if case .moment = self { return true }
        return false
    }
}
