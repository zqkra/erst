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

    private var labels: some View {
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

/// A shortcut to try: its keys, and a line that says whether it has worked yet.
struct ShortcutTry: View {
    let keys: [KeyCap]
    let isDone: Bool
    let doneLine: String

    var body: some View {
        VStack(spacing: Spacing.xxLarge) {
            HStack(spacing: Spacing.small) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in key }
            }
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
        .frame(maxWidth: .infinity)
    }

    private static let modifierWidth = OnboardingLayout.keyModifierWidth
    private static let spaceWidth = OnboardingLayout.spaceKeyWidth

    static func timeline(isDone: Bool) -> ShortcutTry {
        ShortcutTry(
            keys: [
                KeyCap(glyph: "⌥", name: "option", width: modifierWidth, isPressed: isDone),
                KeyCap(glyph: nil, name: "space", width: spaceWidth, isPressed: isDone),
            ],
            isDone: isDone, doneLine: "That is your timeline. It opens over any app.")
    }

    static func search(isDone: Bool) -> ShortcutTry {
        ShortcutTry(
            keys: [
                KeyCap(glyph: "⌥", name: "option", width: modifierWidth, isPressed: isDone),
                KeyCap(glyph: "⇧", name: "shift", width: modifierWidth, isPressed: isDone),
                KeyCap(glyph: nil, name: "space", width: spaceWidth, isPressed: isDone),
            ],
            isDone: isDone, doneLine: "That is search. It opens over any app too.")
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
