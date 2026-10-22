import ErstModel
import SwiftUI

/// What each step asks the user to do.
struct OnboardingStepContent: View {
    let step: OnboardingStep
    let state: OnboardingState
    let actions: OnboardingActions

    var body: some View {
        switch step {
        case .welcome: EmptyView()
        case .permissions: permissions
        case .timeline: ShortcutTry.timeline(isDone: state.hasOpenedTimeline)
        case .search: ShortcutTry.search(isDone: state.hasOpenedSearch)
        case .agents:
            OnboardingAgents(agents: state.agents, error: state.agentError, connect: actions.connect)
        case .ready: OnboardingReady()
        }
    }

    private var permissions: some View {
        VStack(spacing: Spacing.small) {
            OnboardingRow(
                symbol: "display", title: "Screen Recording", subtitle: "To see what is on your screen",
                trailing: state.permissions.screenRecording
                    ? .done("Allowed") : .action("Allow", actions.allowScreenRecording))
            OnboardingRow(
                symbol: "accessibility", title: "Accessibility",
                subtitle: "To read the text in each app and window",
                trailing: state.permissions.accessibility
                    ? .done("Allowed") : .action("Allow", actions.allowAccessibility))
        }
    }
}

/// The agents onboarding suggests, each with its connection. Others, such as Cursor, stay in
/// Settings for whoever uses them.
struct OnboardingAgents: View {
    let agents: [AgentClient]
    let error: String?
    let connect: (AgentClient.Kind) -> Void

    private static let suggested: [AgentClient.Kind] = [.claudeCode, .codex]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ForEach(agents.filter { Self.suggested.contains($0.id) }) { agent in
                OnboardingRow(
                    title: agent.name, subtitle: agent.isInstalled ? "Found on this Mac" : "Not on this Mac",
                    trailing: trailing(for: agent), isDimmed: !agent.isInstalled
                ) {
                    AgentIcon(kind: agent.id)
                }
            }
            if let error {
                Text(error)
                    .erstStyle(Typography.body)
                    .foregroundStyle(Color.erstCoral)
            }
        }
    }

    private func trailing(for agent: AgentClient) -> OnboardingRowTrailing {
        if agent.isConnected { return .done("Connected") }
        if agent.isInstalled { return .action("Connect", { connect(agent.id) }) }
        return .note("Not installed")
    }
}

/// Where Erst lives once onboarding closes, and the two shortcuts that open it.
struct OnboardingReady: View {
    var body: some View {
        VStack(spacing: Spacing.small) {
            OnboardingRow(
                symbol: "menubar.rectangle", title: "In your menu bar",
                subtitle: "Open, pause, or quit Erst from there", trailing: .empty)
            VStack(spacing: 0) {
                ShortcutLine(title: "Open your timeline", keys: ["⌥", "Space"])
                Rectangle()
                    .fill(Color.erstHairline)
                    .frame(height: ControlMetrics.hairlinePoints)
                ShortcutLine(title: "Search everything you saw", keys: ["⌥", "⇧", "Space"])
            }
            .padding(.horizontal, Spacing.large)
            .background {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.erstSurface)
            }
        }
    }
}
