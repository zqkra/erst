import Foundation

/// An agent on this Mac that can read memory through Erst.
public struct AgentClient: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case claudeCode
        case codex
        case cursor
    }

    public let id: Kind
    public var name: String
    public var isInstalled: Bool
    public var isConnected: Bool

    public init(id: Kind, name: String, isInstalled: Bool, isConnected: Bool) {
        self.id = id
        self.name = name
        self.isInstalled = isInstalled
        self.isConnected = isConnected
    }
}

/// Whether a terminal finds the `erst` command.
public enum CommandLineToolState: Hashable, Sendable {
    case notInstalled
    /// `erst` runs the tool inside this copy of Erst.
    case installed
    /// `erst` runs some other file, such as another copy of Erst.
    case otherCopy
}

/// Detects the agents installed on this Mac and connects them to Erst, and puts the `erst` command
/// where a terminal, and any agent that runs commands, finds it.
public protocol AgentClientService: Sendable {
    func clients() async -> [AgentClient]
    func connect(_ kind: AgentClient.Kind) async throws
    func disconnect(_ kind: AgentClient.Kind) async throws
    /// A ready-to-paste MCP configuration for agents Erst does not manage.
    var manualConfiguration: String { get }
    /// Where the command goes, in a folder every macOS shell has on its PATH.
    var commandLinePath: String { get }
    func commandLineState() async -> CommandLineToolState
    /// Links the command to this copy of Erst. macOS asks for an administrator password; a cancel
    /// leaves things as they were and is not an error.
    func installCommandLine() async throws
    func uninstallCommandLine() async throws
}
