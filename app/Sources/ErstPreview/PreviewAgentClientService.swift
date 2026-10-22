import ErstModel
import Foundation

/// Three agents with fixed states for previews and snapshots.
public final class PreviewAgentClientService: AgentClientService, @unchecked Sendable {
    private let lock = NSLock()
    private var storedClients: [AgentClient] = [
        AgentClient(id: .claudeCode, name: "Claude Code", isInstalled: true, isConnected: true),
        AgentClient(id: .codex, name: "Codex", isInstalled: true, isConnected: false),
        AgentClient(id: .cursor, name: "Cursor", isInstalled: false, isConnected: false),
    ]

    private var storedCommandLine: CommandLineToolState

    /// `commandLine` is the state the `erst` command starts in, for a snapshot of each.
    public init(commandLine: CommandLineToolState = .notInstalled) {
        storedCommandLine = commandLine
    }

    public func clients() async -> [AgentClient] {
        readClients()
    }

    public func connect(_ kind: AgentClient.Kind) async throws {
        setConnection(kind, connected: true)
    }

    public func disconnect(_ kind: AgentClient.Kind) async throws {
        setConnection(kind, connected: false)
    }

    public var manualConfiguration: String {
        """
        {
          "mcpServers": {
            "erst": {
              "command": "erst",
              "args": ["mcp"]
            }
          }
        }
        """
    }

    public var commandLinePath: String { "/usr/local/bin/erst" }

    public func commandLineState() async -> CommandLineToolState {
        readCommandLine()
    }

    private func readCommandLine() -> CommandLineToolState {
        lock.lock()
        defer { lock.unlock() }
        return storedCommandLine
    }

    public func installCommandLine() async throws {
        setCommandLine(.installed)
    }

    public func uninstallCommandLine() async throws {
        setCommandLine(.notInstalled)
    }

    private func setCommandLine(_ state: CommandLineToolState) {
        lock.lock()
        defer { lock.unlock() }
        storedCommandLine = state
    }

    private func readClients() -> [AgentClient] {
        lock.lock()
        defer { lock.unlock() }
        return storedClients
    }

    private func setConnection(_ kind: AgentClient.Kind, connected: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = storedClients.firstIndex(where: { $0.id == kind }) else { return }
        storedClients[index].isConnected = connected
    }
}
