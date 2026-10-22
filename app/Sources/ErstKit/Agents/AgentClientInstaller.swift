import ErstModel
import Foundation

/// Serializes configuration edits so calls on one installer cannot overwrite each other's changes.
/// JSON edits retain other keys and values, but can change whitespace and key order.
public actor AgentClientInstaller: AgentClientService {
    private let command: String
    private let arguments: [String]
    private let commandLine: CommandLineLink
    private let homeDirectory: URL
    private let claudeConfiguration: URL
    private let claudeSkills: URL
    private let skill: AgentSkillLink

    /// `skillURL` is the skill bundled with this copy of Erst. Connecting an agent links it into the
    /// agent's skills, so the agent knows when and how to use Erst.
    public init(
        helperURL: URL, dataDirectory: URL?, skillURL: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        command = helperURL.path
        commandLine = CommandLineLink(target: helperURL.path)
        skill = AgentSkillLink(source: skillURL)
        arguments = dataDirectory.map { ["--data-dir", $0.path, "mcp"] } ?? ["mcp"]
        self.homeDirectory = homeDirectory
        let configuredDirectory = environment["CLAUDE_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let claudeDirectory: URL
        if let configuredDirectory, !configuredDirectory.isEmpty {
            claudeDirectory = URL(fileURLWithPath: configuredDirectory, isDirectory: true)
            claudeSkills = claudeDirectory.appendingPathComponent("skills", isDirectory: true)
        } else {
            claudeDirectory = homeDirectory
            claudeSkills = homeDirectory.appendingPathComponent(".claude/skills", isDirectory: true)
        }
        claudeConfiguration = claudeDirectory.appendingPathComponent(".claude.json")
        // Only strings, arrays, and dictionaries are passed to JSONSerialization.
        let manual: [String: Any] = ["mcpServers": ["erst": ["command": command, "args": arguments]]]
        let content = try? JSONSerialization.data(
            withJSONObject: manual, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        manualConfiguration = content.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    public nonisolated let manualConfiguration: String
    public nonisolated var commandLinePath: String { CommandLineLink.path }

    public func commandLineState() async -> CommandLineToolState {
        commandLine.state()
    }

    public func installCommandLine() async throws {
        try await commandLine.install()
    }

    public func uninstallCommandLine() async throws {
        try await commandLine.uninstall()
    }

    public func clients() async -> [AgentClient] {
        [.claudeCode, .codex, .cursor].map { kind in
            AgentClient(
                id: kind, name: name(for: kind),
                isInstalled: isInstalled(kind), isConnected: isConnected(kind)
            )
        }
    }

    public func connect(_ kind: AgentClient.Kind) async throws {
        let file = try AgentConfigurationFile(url: configurationURL(for: kind))
        let content: Data?
        if kind == .codex {
            let configuration = try AgentTOMLConfiguration(content: file.original, file: file.url)
            content = configuration.connect(command: command, arguments: arguments)
        } else {
            var configuration = try AgentJSONConfiguration(content: file.original, file: file.url)
            content = try configuration.connect(
                command: command, arguments: arguments, includesType: kind == .claudeCode
            )
        }
        if let content { try file.write(content) }
        if let skills = skillsDirectory(for: kind) { try skill.install(in: skills) }
    }

    /// Points every agent that has Erst's skill, or is connected, at this copy's skill, so a moved
    /// or updated Erst keeps teaching the agents it already set up.
    public func refreshSkills() async {
        for kind in AgentClient.Kind.allCases {
            guard let skills = skillsDirectory(for: kind),
                skill.isInstalled(in: skills) || isConnected(kind)
            else { continue }
            try? skill.install(in: skills)
        }
    }

    /// Whether `kind` has Erst's skill linked.
    public func hasSkill(_ kind: AgentClient.Kind) async -> Bool {
        skillsDirectory(for: kind).map(skill.isInstalled(in:)) ?? false
    }

    public func disconnect(_ kind: AgentClient.Kind) async throws {
        let file = try AgentConfigurationFile(url: configurationURL(for: kind))
        let content: Data?
        if kind == .codex {
            let configuration = try AgentTOMLConfiguration(content: file.original, file: file.url)
            content = configuration.disconnect()
        } else {
            var configuration = try AgentJSONConfiguration(content: file.original, file: file.url)
            content = try configuration.disconnect()
        }
        if let content { try file.write(content) }
        if let skills = skillsDirectory(for: kind) { try skill.remove(from: skills) }
    }

    /// Where an agent reads skills. Cursor reads none.
    private func skillsDirectory(for kind: AgentClient.Kind) -> URL? {
        switch kind {
        case .claudeCode: claudeSkills
        case .codex: homeDirectory.appendingPathComponent(".codex/skills", isDirectory: true)
        case .cursor: nil
        }
    }

    private func configurationURL(for kind: AgentClient.Kind) -> URL {
        switch kind {
        case .claudeCode: claudeConfiguration
        case .codex: homeDirectory.appendingPathComponent(".codex/config.toml")
        case .cursor: homeDirectory.appendingPathComponent(".cursor/mcp.json")
        }
    }

    private func name(for kind: AgentClient.Kind) -> String {
        switch kind {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    private func isInstalled(_ kind: AgentClient.Kind) -> Bool {
        let files = FileManager.default
        let directory: String
        switch kind {
        case .claudeCode:
            if files.fileExists(atPath: claudeConfiguration.path) { return true }
            directory = ".claude"
        case .codex: directory = ".codex"
        case .cursor: directory = ".cursor"
        }
        return files.fileExists(atPath: homeDirectory.appendingPathComponent(directory).path)
    }

    private func isConnected(_ kind: AgentClient.Kind) -> Bool {
        do {
            let file = try AgentConfigurationFile(url: configurationURL(for: kind))
            if kind == .codex {
                return try AgentTOMLConfiguration(content: file.original, file: file.url)
                    .isConnected(command: command)
            }
            return try AgentJSONConfiguration(content: file.original, file: file.url)
                .isConnected(command: command)
        } catch {
            // Detection cannot throw through AgentClientService. Editing still reports the exact file error.
            return false
        }
    }
}
