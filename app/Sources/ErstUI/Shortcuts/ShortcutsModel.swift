import ErstModel
import Foundation
import Observation

/// The global shortcuts as Settings, the menu bar, and onboarding see them, and the one being
/// recorded. The app applies changes through `actions`; snapshots leave them empty.
@MainActor
@Observable
public final class ShortcutsModel {
    /// What changing a shortcut does. The app fills these in when it registers the shortcuts.
    public struct Actions {
        /// Uses the shortcuts, or answers why they cannot be used.
        public var apply: @MainActor (ShortcutSet) -> ShortcutProblem?
        /// Holds the current shortcuts back while new keys are recorded.
        public var setPaused: @MainActor (Bool) -> Void

        public init(
            apply: @escaping @MainActor (ShortcutSet) -> ShortcutProblem?,
            setPaused: @escaping @MainActor (Bool) -> Void
        ) {
            self.apply = apply
            self.setPaused = setPaused
        }

        public static var none: Actions {
            Actions(apply: { _ in nil }, setPaused: { _ in })
        }
    }

    public var shortcuts: ShortcutSet
    /// The shortcut waiting for new keys, if any. One records at a time.
    public private(set) var recording: GlobalShortcut.Action?
    /// The modifiers held while recording, so the keys appear as they are pressed.
    public private(set) var heldModifiers: GlobalShortcut.Modifiers = []
    /// Why the last keys pressed while recording cannot be used.
    public private(set) var problem: ShortcutProblem?
    @ObservationIgnored public var actions: Actions
    @ObservationIgnored private let keys = ShortcutKeyReader()

    public init(
        shortcuts: ShortcutSet = .default, recording: GlobalShortcut.Action? = nil,
        problem: ShortcutProblem? = nil, actions: Actions = .none
    ) {
        self.shortcuts = shortcuts
        self.recording = recording
        self.problem = problem
        self.actions = actions
    }

    public var isDefault: Bool { shortcuts == .default }

    public func beginRecording(_ action: GlobalShortcut.Action) {
        if recording == nil {
            actions.setPaused(true)
            keys.start(
                onModifiers: { [weak self] in self?.hold($0) },
                onKeys: { [weak self] in self?.record($0) },
                onCancel: { [weak self] in self?.cancelRecording() })
        }
        recording = action
        heldModifiers = []
        problem = nil
    }

    public func cancelRecording() {
        guard recording != nil else { return }
        keys.stop()
        recording = nil
        heldModifiers = []
        problem = nil
        actions.setPaused(false)
    }

    func hold(_ modifiers: GlobalShortcut.Modifiers) {
        heldModifiers = modifiers
        if !modifiers.isEmpty { problem = nil }
    }

    /// Keys pressed while recording: they become the shortcut, or recording goes on with the
    /// reason they cannot.
    public func record(_ shortcut: GlobalShortcut) {
        guard let action = recording else { return }
        heldModifiers = []
        guard shortcut != shortcuts[action] else {
            cancelRecording()
            return
        }
        var proposed = shortcuts
        proposed[action] = shortcut
        if let problem = proposed.problem(for: action) ?? actions.apply(proposed) {
            self.problem = problem
            return
        }
        shortcuts = proposed
        keys.stop()
        recording = nil
        problem = nil
        actions.setPaused(false)
    }

    public func restoreDefaults() {
        cancelRecording()
        if let problem = actions.apply(.default) {
            self.problem = problem
        } else {
            shortcuts = .default
            problem = nil
        }
    }
}
