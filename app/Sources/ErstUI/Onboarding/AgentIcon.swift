import ErstModel
import SwiftUI

/// An agent's own icon, taken from its app on this Mac. An agent whose app is not here gets a
/// quiet symbol instead, since Erst ships no other company's artwork.
struct AgentIcon: View {
    let kind: AgentClient.Kind

    /// Apps whose icon stands for each agent, in the order to try. Claude Code is a command-line
    /// tool, so it borrows the Claude app's icon.
    private static let bundleIdentifiers: [AgentClient.Kind: [String]] = [
        .claudeCode: ["com.anthropic.claudefordesktop"],
        .codex: ["com.openai.codex", "com.openai.chat"],
    ]

    var body: some View {
        if let icon = installedIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: OnboardingLayout.rowIconSide, height: OnboardingLayout.rowIconSide)
        } else {
            RowSymbol(symbol: "terminal", isDimmed: true)
        }
    }

    private var installedIcon: NSImage? {
        for bundleID in Self.bundleIdentifiers[kind] ?? [] {
            let app = AppRef(bundleID: bundleID, name: bundleID)
            let side = OnboardingLayout.rowIconSide
            if let icon = TimelineAppIcons.shared.installedIcon(for: app, size: side) {
                return icon
            }
        }
        return nil
    }
}

/// A symbol on a quiet square, the size of an app icon in a row.
struct RowSymbol: View {
    let symbol: String
    var isDimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: OnboardingLayout.rowIconRadius, style: .continuous)
            .fill(Color.erstCardSelected)
            .frame(width: OnboardingLayout.rowIconSide, height: OnboardingLayout.rowIconSide)
            .overlay {
                Image(systemName: symbol)
                    .font(Typography.icon.font)
                    .foregroundStyle(isDimmed ? Color.erstSecondary : Color.erstText)
            }
    }
}
