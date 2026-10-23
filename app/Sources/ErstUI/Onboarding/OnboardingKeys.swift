import ErstModel
import SwiftUI

/// A key the user is asked to press, drawn like a Mac keycap. It turns butter once the shortcut
/// has worked.
struct KeyCap: View {
    let glyph: String?
    let name: String
    let width: CGFloat
    let isPressed: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: OnboardingLayout.keyRadius, style: .continuous)
                .fill(isPressed ? Color.erstOrange : Color.erstInk)
            RoundedRectangle(cornerRadius: OnboardingLayout.keyRadius, style: .continuous)
                .fill(isPressed ? Color.erstButter : Color.erstCardSelected)
                .padding(.bottom, OnboardingLayout.keyDepth)
            labels
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small + OnboardingLayout.keyDepth)
        }
        .frame(width: width, height: OnboardingLayout.keyHeight)
    }

    @ViewBuilder private var labels: some View {
        if name.isEmpty, let glyph {
            // A letter or a symbol key: one glyph in the middle, as on a Mac keyboard.
            Text(glyph)
                .erstStyle(Typography.keyGlyph)
                .foregroundStyle(isPressed ? Color.erstInk : Color.erstText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            namedLabels
        }
    }

    private var namedLabels: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                if let glyph {
                    Text(glyph).erstStyle(Typography.keyGlyph)
                }
            }
            Spacer(minLength: 0)
            HStack {
                if glyph == nil { Spacer(minLength: 0) }
                Text(name).erstStyle(Typography.caption)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(isPressed ? Color.erstInk : Color.erstText)
    }
}

/// A shortcut to try: its keys, a line that says whether it has worked yet, and a way to pick
/// other keys. While new keys are recorded, the caps follow the modifiers being held.
struct ShortcutTry: View {
    let action: GlobalShortcut.Action
    let shortcuts: ShortcutsModel
    let isDone: Bool
    let doneLine: String

    private var isRecording: Bool { shortcuts.recording == action }

    var body: some View {
        VStack(spacing: Spacing.xxLarge) {
            HStack(spacing: Spacing.small) {
                ForEach(Array(caps.enumerated()), id: \.offset) { _, key in key }
            }
            .opacity(isRecording && shortcuts.heldModifiers.isEmpty ? Self.waitingOpacity : 1)
            VStack(spacing: Spacing.medium) {
                status
                Button(isRecording ? "Cancel" : "Change shortcut") {
                    isRecording ? shortcuts.cancelRecording() : shortcuts.beginRecording(action)
                }
                .buttonStyle(.plain)
                .font(Typography.bodyMedium.font)
                .foregroundStyle(Color.erstSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .shortcutCapture(shortcuts, for: action)
    }

    @ViewBuilder private var status: some View {
        if isRecording {
            Text(shortcuts.problem?.message ?? "Press the keys you want to use")
                .erstStyle(Typography.body)
                .foregroundStyle(shortcuts.problem == nil ? Color.erstText : Color.erstCoral)
        } else {
            HStack(spacing: Spacing.small) {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.erstButter)
                }
                Text(isDone ? doneLine : "Waiting for you to press it")
                    .erstStyle(Typography.body)
                    .foregroundStyle(isDone ? Color.erstText : Color.erstSecondary)
            }
        }
    }

    /// The caps of the chosen shortcut, or of the modifiers held while new keys are recorded.
    private var caps: [KeyCap] {
        let shortcut = shortcuts.shortcuts[action]
        guard isRecording, !shortcuts.heldModifiers.isEmpty else {
            return Self.caps(for: shortcut.modifiers, isPressed: isDone) + [
                Self.cap(for: shortcut, isPressed: isDone)
            ]
        }
        return Self.caps(for: shortcuts.heldModifiers, isPressed: false)
    }

    private static let waitingOpacity = 0.35
    private static let modifierWidth = OnboardingLayout.keyModifierWidth
    private static let spaceWidth = OnboardingLayout.spaceKeyWidth
    private static let wideKeyWidth = OnboardingLayout.wideKeyWidth

    private static func caps(for modifiers: GlobalShortcut.Modifiers, isPressed: Bool) -> [KeyCap] {
        modifiers.parts.map {
            KeyCap(glyph: $0.glyph, name: $0.keyName, width: modifierWidth, isPressed: isPressed)
        }
    }

    /// Space is the long bar, a letter or symbol sits in the middle of its cap, and a named key
    /// such as Return or F5 writes its name at the bottom, as Mac keyboards do.
    private static func cap(for shortcut: GlobalShortcut, isPressed: Bool) -> KeyCap {
        if shortcut.isSpace {
            return KeyCap(glyph: nil, name: "space", width: spaceWidth, isPressed: isPressed)
        }
        if shortcut.key.count == 1 {
            return KeyCap(glyph: shortcut.key, name: "", width: modifierWidth, isPressed: isPressed)
        }
        let width = shortcut.isFunctionKey ? modifierWidth : wideKeyWidth
        return KeyCap(glyph: nil, name: shortcut.key.lowercased(), width: width, isPressed: isPressed)
    }
}

/// A shortcut written as small keycaps, for the ready step.
struct ShortcutLine: View {
    let title: String
    let keys: [String]

    var body: some View {
        HStack {
            Text(title)
                .erstStyle(Typography.headline)
                .foregroundStyle(Color.erstText)
            Spacer(minLength: Spacing.small)
            HStack(spacing: Spacing.xSmall) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .erstStyle(Typography.bodyMedium)
                        .foregroundStyle(Color.erstText)
                        .padding(.horizontal, Spacing.small)
                        .frame(minWidth: OnboardingLayout.smallKeyHeight)
                        .frame(height: OnboardingLayout.smallKeyHeight - OnboardingLayout.smallKeyDepth)
                        .background {
                            smallKey.fill(Color.erstCardSelected)
                        }
                        .padding(.bottom, OnboardingLayout.smallKeyDepth)
                        .background(alignment: .bottom) {
                            smallKey.fill(Color.erstInk)
                        }
                }
            }
        }
        .frame(height: OnboardingLayout.rowHeight - Spacing.medium)
    }

    private var smallKey: RoundedRectangle {
        RoundedRectangle(cornerRadius: OnboardingLayout.smallKeyRadius, style: .continuous)
    }
}
