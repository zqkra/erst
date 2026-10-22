import SwiftUI

/// A command in the menu bar window, in menu order.
enum MenuBarAction: Hashable {
    case openTimeline
    case search
    case activity
    case pause
    case resume
    case settings
    case quit

    /// The commands above the last separator. Pause turns into Resume while recording is off,
    /// so the menu needs no switch: quitting Erst is how recording stops for good.
    static func commands(isPaused: Bool) -> [MenuBarAction] {
        [.openTimeline, .search, .activity, isPaused ? .resume : .pause]
    }

    /// Settings and Quit close every macOS menu, under their own separator.
    static let application: [MenuBarAction] = [.settings, .quit]

    /// Every row in menu order, for the arrow keys.
    static func rows(isPaused: Bool) -> [MenuBarAction] {
        commands(isPaused: isPaused) + application
    }

    /// Menu items take title capitalization, as in every macOS menu.
    var title: String {
        switch self {
        case .openTimeline: "Open Timeline"
        case .search: "Search"
        case .activity: "Activity"
        case .pause: "Pause for an Hour"
        case .resume: "Resume Recording"
        case .settings: "Settings\u{2026}"
        case .quit: "Quit Erst"
        }
    }

    /// The glyphs shown at the trailing edge. The overlay shortcuts are global; Settings and Quit
    /// also work while the window is open, through `keyboardShortcut`.
    var shortcut: String? {
        switch self {
        case .openTimeline: "\u{2325}Space"
        case .search: "\u{2325}\u{21E7}Space"
        case .activity, .pause, .resume: nil
        case .settings: "\u{2318},"
        case .quit: "\u{2318}Q"
        }
    }

    var keyboardShortcut: KeyboardShortcut? {
        switch self {
        case .settings: KeyboardShortcut(",", modifiers: .command)
        case .quit: KeyboardShortcut("q", modifiers: .command)
        case .openTimeline, .search, .activity, .pause, .resume: nil
        }
    }
}

/// One command row. The pointer and the arrow keys share one highlight, like a menu item.
struct MenuBarRow: View {
    let action: MenuBarAction
    let isHighlighted: Bool
    let onHover: (Bool) -> Void
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: Spacing.small) {
                Text(action.title)
                    .erstStyle(Typography.body)
                    .foregroundStyle(Color.erstText)
                Spacer(minLength: Spacing.small)
                if let shortcut = action.shortcut {
                    Text(shortcut)
                        .erstStyle(Typography.body)
                        .foregroundStyle(Color.erstSecondary)
                }
            }
        }
        .buttonStyle(MenuBarRowStyle(isHighlighted: isHighlighted))
        .keyboardShortcut(action.keyboardShortcut)
        .onHover(perform: onHover)
    }
}

/// Fills the row while it is highlighted and a step brighter while it is pressed.
private struct MenuBarRowStyle: ButtonStyle {
    let isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, MenuBarLayout.contentInset - MenuBarLayout.rowInset)
            .frame(height: MenuBarLayout.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .fill(fill(isPressed: configuration.isPressed))
            }
            .contentShape(Rectangle())
            .padding(.horizontal, MenuBarLayout.rowInset)
    }

    private func fill(isPressed: Bool) -> Color {
        if isPressed { return .erstRowPressed }
        return isHighlighted ? .erstRowHighlight : .clear
    }
}

/// A quiet label over a group of rows.
struct MenuBarSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .erstStyle(Typography.eyebrow)
            .foregroundStyle(Color.erstSecondary)
            .frame(height: MenuBarLayout.sectionTitleHeight, alignment: .center)
            .padding(.horizontal, MenuBarLayout.contentInset)
            .accessibilityAddTraits(.isHeader)
    }
}
