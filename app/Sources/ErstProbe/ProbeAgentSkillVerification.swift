import ErstKit
import Foundation

/// Proves that connecting an agent links Erst's skill where the agent reads skills, through the
/// installer the app uses, on a temporary home folder: connecting links it, a moved Erst relinks
/// it, a folder the user made under the same name is left alone, and disconnecting removes it.
enum ProbeAgentSkillVerification {
    private enum Failure: Error {
        case check(String)
    }

    static func run() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("erst-skill-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let firstCopy = try makeBundledSkill(in: home.appendingPathComponent("Old/Erst.app"))
        let secondCopy = try makeBundledSkill(in: home.appendingPathComponent("Applications/Erst.app"))
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let claudeLink = home.appendingPathComponent(".claude/skills/erst")
        let codexLink = home.appendingPathComponent(".codex/skills/erst")

        let first = installer(home: home, skill: firstCopy)
        try await first.connect(.claudeCode)
        try await first.connect(.codex)
        try expectLink(claudeLink, to: firstCopy, "Connecting Claude Code must link the skill")
        try expectLink(codexLink, to: firstCopy, "Connecting Codex must link the skill")

        let moved = installer(home: home, skill: secondCopy)
        await moved.refreshSkills()
        try expectLink(claudeLink, to: secondCopy, "A moved Erst must relink the skill of a connected agent")

        try await moved.disconnect(.codex)
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: codexLink.path)) == nil else {
            throw Failure.check("Disconnecting Codex must remove its skill link")
        }

        try await moved.disconnect(.claudeCode)
        try FileManager.default.createDirectory(at: claudeLink, withIntermediateDirectories: true)
        try await moved.connect(.claudeCode)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: claudeLink.path, isDirectory: &isDirectory),
            isDirectory.boolValue,
            (try? FileManager.default.destinationOfSymbolicLink(atPath: claudeLink.path)) == nil
        else {
            throw Failure.check("A folder the user made under the skill's name must be left alone")
        }
        print(
            "Agent skill verification passed: linked on connect, relinked after a move, user folder kept, removed on disconnect"
        )
    }

    private static func installer(home: URL, skill: URL) -> AgentClientInstaller {
        AgentClientInstaller(
            helperURL: skill.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Helpers/erst"),
            dataDirectory: nil, skillURL: skill, homeDirectory: home, environment: [:])
    }

    /// A copy of the skill where the build puts it inside an app bundle.
    private static func makeBundledSkill(in bundle: URL) throws -> URL {
        let skill = bundle.appendingPathComponent("Contents/Resources/skill/erst", isDirectory: true)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try Data("---\nname: erst\n---\n".utf8).write(to: skill.appendingPathComponent("SKILL.md"))
        return skill
    }

    private static func expectLink(_ link: URL, to skill: URL, _ message: String) throws {
        let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        guard destination == skill.path,
            FileManager.default.fileExists(atPath: link.appendingPathComponent("SKILL.md").path)
        else {
            throw Failure.check("\(message): \(link.path) points to \(destination ?? "nothing")")
        }
    }
}
