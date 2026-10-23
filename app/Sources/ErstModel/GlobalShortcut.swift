import Foundation

/// A shortcut that opens Erst from any app: one key and its modifiers, as macOS reports them.
public struct GlobalShortcut: Codable, Hashable, Sendable {
    /// What a global shortcut opens.
    public enum Action: String, CaseIterable, Codable, Hashable, Sendable {
        case timeline
        case search

        public var title: String {
            switch self {
            case .timeline: "Open timeline"
            case .search: "Search everything"
            }
        }
    }

    /// The modifier keys, in the order Apple writes them: Control, Option, Shift, Command.
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// Each modifier held, in Apple's order, with its glyph, the name on its key, and the
        /// name said in a sentence.
        public var parts: [(glyph: String, keyName: String, spoken: String)] {
            Self.order.filter { contains($0.modifier) }.map { ($0.glyph, $0.keyName, $0.spoken) }
        }

        private static let order: [(modifier: Modifiers, glyph: String, keyName: String, spoken: String)] = [
            (.control, "\u{2303}", "control", "Control"),
            (.option, "\u{2325}", "option", "Option"),
            (.shift, "\u{21E7}", "shift", "Shift"),
            (.command, "\u{2318}", "command", "Command"),
        ]
    }

    /// The virtual key code macOS reports, such as 49 for Space.
    public let keyCode: UInt16
    public let modifiers: Modifiers
    /// What the key's cap reads, such as "Space", "K", or "F5". The letter on a key depends on the
    /// keyboard layout, so it is kept as it was when the shortcut was recorded.
    public let key: String

    public init(keyCode: UInt16, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// The key a shortcut needs when it is recorded: the name of a key that types nothing, or the
    /// character the key types without modifiers.
    public static func keyName(keyCode: UInt16, character: String) -> String {
        if let special = specialKeys[keyCode] { return special.cap }
        let trimmed = character.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Key \(keyCode)" : trimmed.uppercased()
    }

    /// The shortcut as menus write it, such as "⌥Space".
    public var menuText: String {
        modifiers.parts.map(\.glyph).joined() + key
    }

    /// The keys one by one, for keycaps: each modifier's glyph and name, then the key.
    public var keys: [String] {
        modifiers.parts.map(\.glyph) + [key]
    }

    /// The shortcut in a sentence, such as "Option, Shift and Space".
    public var spokenText: String {
        let names = modifiers.parts.map(\.spoken) + [Self.specialKeys[keyCode]?.spoken ?? key]
        guard names.count > 1 else { return names.joined() }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    public var isSpace: Bool { keyCode == Self.spaceKeyCode }

    /// F1 to F20 type nothing, so they work without a modifier.
    public var isFunctionKey: Bool { Self.functionKeys.contains(keyCode) }

    static let spaceKeyCode: UInt16 = 49
    public static let escapeKeyCode: UInt16 = 53

    /// F1 to F20, in order.
    private static let functionKeys: [UInt16] = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    /// Keys that type nothing printable, named as their caps read and as a sentence says them.
    private static let specialKeys: [UInt16: (cap: String, spoken: String)] = {
        var keys: [UInt16: (cap: String, spoken: String)] = [
            49: ("Space", "Space"), 36: ("Return", "Return"), 76: ("Enter", "Enter"), 48: ("Tab", "Tab"),
            51: ("Delete", "Delete"), 117: ("\u{2326}", "Forward Delete"), 53: ("Escape", "Escape"),
            123: ("\u{2190}", "Left Arrow"), 124: ("\u{2192}", "Right Arrow"),
            125: ("\u{2193}", "Down Arrow"), 126: ("\u{2191}", "Up Arrow"),
            115: ("Home", "Home"), 119: ("End", "End"), 116: ("Page Up", "Page Up"),
            121: ("Page Down", "Page Down"),
        ]
        for (index, code) in functionKeys.enumerated() {
            keys[code] = ("F\(index + 1)", "F\(index + 1)")
        }
        return keys
    }()
}

/// Both global shortcuts.
public struct ShortcutSet: Codable, Hashable, Sendable {
    public var timeline: GlobalShortcut
    public var search: GlobalShortcut

    public init(timeline: GlobalShortcut, search: GlobalShortcut) {
        self.timeline = timeline
        self.search = search
    }

    /// Option-Space opens the timeline, the way into everything; Shift goes straight to search.
    public static let `default` = ShortcutSet(
        timeline: GlobalShortcut(keyCode: GlobalShortcut.spaceKeyCode, modifiers: .option, key: "Space"),
        search: GlobalShortcut(
            keyCode: GlobalShortcut.spaceKeyCode, modifiers: [.option, .shift], key: "Space")
    )

    public subscript(action: GlobalShortcut.Action) -> GlobalShortcut {
        get {
            switch action {
            case .timeline: timeline
            case .search: search
            }
        }
        set {
            switch action {
            case .timeline: timeline = newValue
            case .search: search = newValue
            }
        }
    }

    /// Why `action`'s shortcut cannot be used, from the keys alone. Whether macOS or another app
    /// already holds it is only known when it is registered.
    public func problem(for action: GlobalShortcut.Action) -> ShortcutProblem? {
        let shortcut = self[action]
        if !shortcut.isFunctionKey {
            if shortcut.modifiers.isDisjoint(with: [.command, .option, .control]) {
                return .needsModifier
            }
            // Command alone, or with Shift, is how every app names its own commands, so taking it
            // everywhere would break copy, undo, or quit in other apps.
            if shortcut.modifiers.isSubset(of: [.command, .shift]) {
                return .usedByApps
            }
        }
        for other in GlobalShortcut.Action.allCases where other != action && self[other] == shortcut {
            return .usedByOtherAction(other)
        }
        return nil
    }
}

/// Why a shortcut cannot be used.
public enum ShortcutProblem: Error, Hashable, Sendable {
    case needsModifier
    case usedByApps
    case usedByOtherAction(GlobalShortcut.Action)
    case usedByMacOS
    case usedByAnotherApp

    public var message: String {
        switch self {
        case .needsModifier: "Hold Command, Option, or Control with the key."
        case .usedByApps: "Apps use this for their own commands. Add Option or Control."
        case .usedByOtherAction(let action): "\(action.title) already uses this shortcut."
        case .usedByMacOS: "macOS already uses this shortcut."
        case .usedByAnotherApp: "Another app already uses this shortcut."
        }
    }
}
