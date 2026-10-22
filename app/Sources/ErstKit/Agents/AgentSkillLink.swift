import Foundation

/// The skill that teaches an agent when and how to use Erst, linked into the agent's skills folder.
///
/// The link points into the app bundle, so the skill updates with Erst. Only a link that points to
/// an Erst skill is ever replaced or removed; a folder the user made under the same name is left
/// alone.
struct AgentSkillLink {
    static let name = "erst"
    /// The part of the path every copy of the bundled skill ends with, wherever Erst is installed.
    private static let bundledSuffix = "/Contents/Resources/skill/\(name)"

    /// The skill inside this copy of Erst. Nil when it is missing, as in a build from source.
    let source: URL?

    /// Links the skill into `skills`, creating the folder when the agent has none yet.
    func install(in skills: URL) throws {
        guard let source, FileManager.default.fileExists(atPath: source.path) else { return }
        let files = FileManager.default
        let link = skills.appendingPathComponent(Self.name)
        if let current = destination(of: link) {
            guard current != source.path else { return }
            guard Self.isErstSkill(current) else { return }
            try files.removeItem(at: link)
        } else if files.fileExists(atPath: link.path) {
            // The user's own folder under this name.
            return
        }
        try files.createDirectory(at: skills, withIntermediateDirectories: true)
        try files.createSymbolicLink(at: link, withDestinationURL: source)
    }

    /// Removes the link when it points to an Erst skill.
    func remove(from skills: URL) throws {
        let link = skills.appendingPathComponent(Self.name)
        guard let current = destination(of: link), Self.isErstSkill(current) else { return }
        try FileManager.default.removeItem(at: link)
    }

    /// Whether `skills` holds a link to an Erst skill.
    func isInstalled(in skills: URL) -> Bool {
        destination(of: skills.appendingPathComponent(Self.name)).map(Self.isErstSkill) ?? false
    }

    private func destination(of link: URL) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
    }

    private static func isErstSkill(_ path: String) -> Bool {
        path.hasSuffix(bundledSuffix)
    }
}
