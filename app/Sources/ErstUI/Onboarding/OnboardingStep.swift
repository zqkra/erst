import ErstModel
import Foundation

/// The steps of first launch. After the welcome and the permissions, each step teaches by doing:
/// the user presses the real shortcuts and connects real agents.
public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case permissions
    case timeline
    case search
    case agents
    case ready

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .welcome: "Every moment leaves an echo."
        case .permissions: "Let Erst see your screen"
        case .timeline: "Go back to any moment"
        case .search: "Find anything you saw"
        case .agents: "Let your agents remember too"
        case .ready: "Erst is remembering"
        }
    }

    /// What the step asks, naming the shortcuts the user chose.
    public func detail(shortcuts: ShortcutSet = .default) -> String {
        switch self {
        case .welcome:
            "Erst remembers what you see on your screen, so you can find it again. It all stays on this Mac."
        case .permissions:
            "Erst reads the text on your screen and keeps it on this Mac. Nothing is sent anywhere."
        case .timeline:
            "Press \(shortcuts.timeline.spokenText) together. Your timeline opens over everything. Press Escape to come back here."
        case .search:
            "Press \(shortcuts.search.spokenText), then type a word you saw a minute ago."
        case .agents:
            "Your coding agents can ask Erst what you saw, only when you ask them to. Try \u{201C}What was that article I read this morning?\u{201D}"
        case .ready:
            "It lives in your menu bar, where you can pause it at any time. Two shortcuts are all you need."
        }
    }

    public var actionTitle: String {
        switch self {
        case .welcome: "Get started"
        case .ready: "Done"
        case .permissions, .timeline, .search, .agents: "Continue"
        }
    }

    /// How many parts of the footer's e are hot: one per step finished after the welcome.
    public var heatedParts: Int {
        min(max(rawValue, 0), ProgressMarkArt.partCount)
    }

    /// The footer's words next to the e.
    public var progressTitle: String {
        self == .ready ? "All set" : "Step \(rawValue) of \(ProgressMarkArt.partCount)"
    }

    /// Steps that teach a shortcut can be skipped; the others gate on what they ask for.
    public var isSkippable: Bool {
        self == .timeline || self == .search
    }
}
