import Carbon
import ErstModel
import Foundation
import os

private let globalHotKeysLog = Logger(subsystem: "app.erst.Erst", category: "GlobalHotKeys")

/// The global shortcuts the user chose: kept in the app's preferences and registered with macOS.
@MainActor
public final class GlobalHotKeys {
    private static let storageKey = "globalShortcuts"

    public private(set) var shortcuts: ShortcutSet
    private let center = HotKeyCenter()
    private let handler: @MainActor @Sendable (GlobalShortcut.Action) -> Void
    private var isPaused = false

    /// Loads the saved shortcuts, or the defaults, and registers them. `handler` runs when one is
    /// pressed.
    public init(handler: @escaping @MainActor @Sendable (GlobalShortcut.Action) -> Void) {
        self.handler = handler
        shortcuts = Self.saved() ?? .default
        if !register(shortcuts) {
            globalHotKeysLog.error("A saved shortcut is taken by another app; it does not work until changed")
        }
    }

    /// Uses `proposed` when macOS and other apps leave its shortcuts free, and saves it. Otherwise
    /// the current shortcuts stay and the answer says why. A pause stays in effect.
    public func apply(_ proposed: ShortcutSet) -> ShortcutProblem? {
        for action in GlobalShortcut.Action.allCases where proposed[action] != shortcuts[action] {
            if let problem = proposed.problem(for: action) { return problem }
            if Self.isUsedByMacOS(proposed[action]) { return .usedByMacOS }
        }
        // Registering is the only way to learn whether another app holds a shortcut.
        center.unregisterAll()
        guard register(proposed) else {
            center.unregisterAll()
            if !isPaused { register(shortcuts) }
            return .usedByAnotherApp
        }
        shortcuts = proposed
        if let data = try? JSONEncoder().encode(proposed) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        if isPaused { center.unregisterAll() }
        return nil
    }

    /// While the user records a new shortcut, the current ones must not fire.
    public func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            center.unregisterAll()
        } else {
            register(shortcuts)
        }
    }

    public func unregisterAll() {
        center.unregisterAll()
    }

    /// Registers every shortcut in `set`, and answers whether all of them took.
    @discardableResult
    private func register(_ set: ShortcutSet) -> Bool {
        var registeredAll = true
        for action in GlobalShortcut.Action.allCases {
            let handler = handler
            registeredAll =
                center.register(HotKeyShortcut(set[action]), identifier: action.rawValue) { handler(action) }
                && registeredAll
        }
        return registeredAll
    }

    private static func saved() -> ShortcutSet? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(ShortcutSet.self, from: data)
    }

    /// Whether an enabled system shortcut, such as Spotlight's Command-Space, uses these keys.
    /// Registering one of them succeeds, but macOS keeps the key press for itself.
    private static func isUsedByMacOS(_ shortcut: GlobalShortcut) -> Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
            let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return false }
        let wanted = HotKeyShortcut(shortcut)
        let mask = UInt32(cmdKey | optionKey | shiftKey | controlKey)
        return entries.contains { entry in
            guard (entry["kHISymbolicHotKeyEnabled"] as? Bool) == true,
                let code = entry["kHISymbolicHotKeyCode"] as? Int,
                let modifiers = entry["kHISymbolicHotKeyModifiers"] as? Int
            else { return false }
            return UInt32(code) == wanted.keyCode && UInt32(modifiers) & mask == wanted.modifiers
        }
    }
}

extension HotKeyShortcut {
    /// The Carbon form of a shortcut.
    public init(_ shortcut: GlobalShortcut) {
        var modifiers = 0
        if shortcut.modifiers.contains(.control) { modifiers |= controlKey }
        if shortcut.modifiers.contains(.option) { modifiers |= optionKey }
        if shortcut.modifiers.contains(.shift) { modifiers |= shiftKey }
        if shortcut.modifiers.contains(.command) { modifiers |= cmdKey }
        self.init(keyCode: UInt32(shortcut.keyCode), modifiers: UInt32(modifiers))
    }
}
