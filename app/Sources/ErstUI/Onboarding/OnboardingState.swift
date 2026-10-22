import ErstModel
import Foundation

/// What onboarding shows: the permissions, which shortcuts the user has tried, and the agents.
public struct OnboardingState: Hashable, Sendable {
    public var permissions: PermissionsState
    public var hasOpenedTimeline: Bool
    public var hasOpenedSearch: Bool
    public var agents: [AgentClient]
    /// The last agent connection that failed, said in a sentence.
    public var agentError: String?

    public init(
        permissions: PermissionsState, hasOpenedTimeline: Bool = false, hasOpenedSearch: Bool = false,
        agents: [AgentClient] = [], agentError: String? = nil
    ) {
        self.permissions = permissions
        self.hasOpenedTimeline = hasOpenedTimeline
        self.hasOpenedSearch = hasOpenedSearch
        self.agents = agents
        self.agentError = agentError
    }

    /// Whether `step` is done enough to continue.
    public func allowsContinue(on step: OnboardingStep) -> Bool {
        switch step {
        case .permissions: permissions.isComplete
        case .timeline: hasOpenedTimeline
        case .search: hasOpenedSearch
        case .welcome, .agents, .ready: true
        }
    }
}

/// What the user can do from onboarding.
public struct OnboardingActions {
    public var allowScreenRecording: () -> Void
    public var allowAccessibility: () -> Void
    public var connect: (AgentClient.Kind) -> Void
    public var proceed: () -> Void
    public var skip: () -> Void

    public init(
        allowScreenRecording: @escaping () -> Void = {}, allowAccessibility: @escaping () -> Void = {},
        connect: @escaping (AgentClient.Kind) -> Void = { _ in }, proceed: @escaping () -> Void = {},
        skip: @escaping () -> Void = {}
    ) {
        self.allowScreenRecording = allowScreenRecording
        self.allowAccessibility = allowAccessibility
        self.connect = connect
        self.proceed = proceed
        self.skip = skip
    }
}
