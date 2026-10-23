import ErstModel
import ErstUI
import Foundation

/// Checks the rules for global shortcuts and the recording that Settings and onboarding share.
@MainActor
enum ShortcutContract {
    static func verify() throws {
        let defaults = ShortcutSet.default
        try require(
            defaults.timeline.menuText == "\u{2325}Space"
                && defaults.search.menuText == "\u{2325}\u{21E7}Space",
            "Menus write the default shortcuts as Option-Space and Option-Shift-Space.")
        try require(
            OnboardingStep.timeline.detail(shortcuts: defaults).hasPrefix("Press Option and Space together.")
                && OnboardingStep.search.detail(shortcuts: defaults).hasPrefix(
                    "Press Option, Shift and Space,"),
            "Onboarding names the default shortcuts as it always did.")
        try require(
            GlobalShortcut.keyName(keyCode: 40, character: "k") == "K"
                && GlobalShortcut.keyName(keyCode: 49, character: " ") == "Space"
                && GlobalShortcut.keyName(keyCode: 96, character: "") == "F5",
            "A recorded key reads as its cap: K, Space, F5.")
        try rules(defaults)
        try recording()
    }

    private static let controlOptionK = GlobalShortcut(keyCode: 40, modifiers: [.control, .option], key: "K")

    private static func rules(_ defaults: ShortcutSet) throws {
        func problem(_ shortcut: GlobalShortcut) -> ShortcutProblem? {
            var set = defaults
            set.timeline = shortcut
            return set.problem(for: .timeline)
        }
        func k(_ modifiers: GlobalShortcut.Modifiers) -> GlobalShortcut {
            GlobalShortcut(keyCode: 40, modifiers: modifiers, key: "K")
        }
        try require(
            problem(k([])) == .needsModifier && problem(k(.shift)) == .needsModifier,
            "A key alone, or with Shift only, would fire while typing.")
        try require(
            problem(k(.command)) == .usedByApps && problem(k([.command, .shift])) == .usedByApps,
            "Command and Command-Shift with a key belong to every app's own commands.")
        try require(problem(controlOptionK) == nil, "Control-Option-K is free to use.")
        try require(
            problem(GlobalShortcut(keyCode: 96, modifiers: [], key: "F5")) == nil,
            "A function key works alone.")
        try require(
            problem(defaults.search) == .usedByOtherAction(.search), "Two global shortcuts cannot share keys."
        )
    }

    /// Recording pauses the shortcuts, refuses keys it cannot use without leaving, applies keys it
    /// can, and keeps the old shortcut when macOS or another app holds the new one.
    private static func recording() throws {
        let log = ActionLog()
        let model = ShortcutsModel(
            actions: ShortcutsModel.Actions(
                apply: { proposed in
                    if log.refuses { return .usedByAnotherApp }
                    log.applied.append(proposed)
                    return nil
                },
                setPaused: { log.paused.append($0) }))
        model.beginRecording(.timeline)
        try require(
            log.paused == [true], "Recording pauses the global shortcuts, so the old keys do not fire.")
        model.record(GlobalShortcut(keyCode: 40, modifiers: [], key: "K"))
        try require(
            model.recording == .timeline && model.problem == .needsModifier && log.applied.isEmpty,
            "Keys that cannot be used leave recording on and say why.")
        model.record(controlOptionK)
        try require(
            model.shortcuts.timeline == controlOptionK && model.recording == nil && log.paused.last == false
                && log.applied.count == 1,
            "Usable keys become the shortcut and the shortcuts work again.")
        try require(
            OnboardingStep.timeline.detail(shortcuts: model.shortcuts).hasPrefix(
                "Press Control, Option and K together."),
            "Onboarding names the shortcut the user chose.")
        log.refuses = true
        model.beginRecording(.search)
        model.record(GlobalShortcut(keyCode: 38, modifiers: [.control, .option], key: "J"))
        try require(
            model.problem == .usedByAnotherApp && model.shortcuts.search == ShortcutSet.default.search,
            "A shortcut another app holds is refused and the old one stays.")
        model.cancelRecording()
        try require(
            model.recording == nil && model.problem == nil && log.paused.last == false,
            "Cancelling restores the shortcuts.")
        log.refuses = false
        model.restoreDefaults()
        try require(
            model.shortcuts == .default && model.isDefault, "Restore Defaults brings back Option-Space.")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SnapshotError.contract(message) }
    }
}

@MainActor
private final class ActionLog {
    var applied: [ShortcutSet] = []
    var paused: [Bool] = []
    var refuses = false
}
