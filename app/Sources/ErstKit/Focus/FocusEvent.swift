import Foundation

/// A focus change, an idle transition, or a return from idle.
public enum FocusEvent: Sendable, Equatable {
    /// The focused app, window, or page changed.
    case changed(FocusContext)
    /// The user has been idle since the given time.
    case idle(since: Date)
    /// Activity resumed after an idle period.
    case resumed(at: Date)
}
