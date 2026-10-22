import Foundation

/// Codex configuration edits. Only the command and args values of the Erst entry
/// are replaced, so user keys inside that entry survive reconnects.
struct AgentTOMLConfiguration {
    static let separatorComment = "# Erst added the preceding newline."

    private struct Entry {
        let start: Int
        let bodyStart: Int
        let end: Int
        let insertedSeparator: Bool
        let command: AgentTOMLScanner.Assignment?
        let args: AgentTOMLScanner.Assignment?
        let commandValue: String?
    }

    private let bytes: [UInt8]
    private let document: AgentTOMLScanner.Document
    private let entry: Entry?
    private let lineEnding: String

    init(content: Data?, file: URL) throws {
        let content = content ?? Data()
        guard String(data: content, encoding: .utf8) != nil else {
            throw AgentClientError.invalidConfiguration(file: file, reason: "Expected UTF-8 TOML text.")
        }
        bytes = Array(content)
        document = try AgentTOMLScanner(bytes: bytes, file: file).scan()
        entry = try Self.entry(in: document, file: file)
        let raw = bytes
        let firstNewline = raw.firstIndex(of: 10)
        lineEnding =
            firstNewline.map { $0 > 0 && raw[$0 - 1] == 13 ? "\r\n" : "\n" } ?? "\n"
    }

    func isConnected(command: String) -> Bool {
        entry?.commandValue == command
    }

    func connect(command: String, arguments: [String]) -> Data? {
        let args = arguments.map(AgentTOMLString.quoted).joined(separator: ", ")
        let commandLine = "command = \(AgentTOMLString.quoted(command))"
        let argsLine = "args = [\(args)]"
        guard let entry else {
            return appending(commandLine: commandLine, argsLine: argsLine)
        }
        var edits: [(range: Range<Int>, bytes: [UInt8])] = []
        if let assignment = entry.command {
            edits.append(
                (assignment.valueStart..<assignment.valueEnd, Array(AgentTOMLString.quoted(command).utf8)))
        }
        if let assignment = entry.args {
            edits.append((assignment.valueStart..<assignment.valueEnd, Array("[\(args)]".utf8)))
        }
        var inserted: [UInt8] = []
        var insertionPoint = entry.bodyStart
        if let assignment = entry.command, entry.args == nil {
            insertionPoint = assignment.lineEnd
            inserted = Array((argsLine + lineEnding).utf8)
        } else if entry.command == nil, let assignment = entry.args {
            insertionPoint = assignment.lineStart
            inserted = Array((commandLine + lineEnding).utf8)
        } else if entry.command == nil {
            inserted = Array((commandLine + lineEnding + argsLine + lineEnding).utf8)
        }
        if !inserted.isEmpty, insertionPoint > 0, bytes[insertionPoint - 1] != 10 {
            inserted.insert(contentsOf: Array(lineEnding.utf8), at: 0)
        }
        if !inserted.isEmpty {
            edits.append((insertionPoint..<insertionPoint, inserted))
        }
        var updated = bytes
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            updated.replaceSubrange(edit.range, with: edit.bytes)
        }
        return updated == bytes ? nil : Data(updated)
    }

    func disconnect() -> Data? {
        guard let entry else { return nil }
        var updated = bytes
        updated.removeSubrange((entry.start - separatorLength(for: entry))..<entry.end)
        return Data(updated)
    }

    private func appending(commandLine: String, argsLine: String) -> Data? {
        let hasContent = bytes.count > document.bomLength
        let needsSeparator = hasContent && bytes.last != 10
        let comment = needsSeparator ? " \(Self.separatorComment)" : ""
        let table = ["[mcp_servers.erst]\(comment)", commandLine, argsLine, ""].joined(
            separator: lineEnding)
        var updated = bytes
        if needsSeparator { updated.append(contentsOf: Array(lineEnding.utf8)) }
        updated.append(contentsOf: table.utf8)
        return updated == bytes ? nil : Data(updated)
    }

    /// The newline that Erst added before the table, if it is still at the end of the file.
    private func separatorLength(for entry: Entry) -> Int {
        guard entry.insertedSeparator, entry.end == bytes.count, entry.start > 0,
            bytes[entry.start - 1] == 10
        else {
            return 0
        }
        return entry.start > 1 && bytes[entry.start - 2] == 13 ? 2 : 1
    }

    private static func entry(in document: AgentTOMLScanner.Document, file: URL) throws -> Entry? {
        if document.tables.contains(where: { $0.isArray && $0.keys == ["mcp_servers"] }) {
            throw unsupported(file)
        }
        if document.tables.contains(where: {
            $0.isArray && $0.keys == ["mcp_servers", "erst"]
        }) {
            throw unsupported(file)
        }
        if document.assignments.contains(where: { declaresErst($0, in: document) }) {
            throw unsupported(file)
        }
        let matches = document.tables.indices.filter {
            document.tables[$0].keys == ["mcp_servers", "erst"]
        }
        guard matches.count <= 1 else {
            throw AgentClientError.invalidConfiguration(
                file: file, reason: "The Erst table appears more than once.")
        }
        guard let index = matches.first else { return nil }
        let table = document.tables[index]
        let end =
            index + 1 < document.tables.count
            ? document.tables[index + 1].start : document.bytes.count
        let assignments = document.assignments.filter { $0.tableIndex == index }
        let commands = assignments.filter { $0.keys == ["command"] }
        let arguments = assignments.filter { $0.keys == ["args"] }
        guard commands.count <= 1, arguments.count <= 1 else {
            throw AgentClientError.invalidConfiguration(
                file: file, reason: "The Erst table defines command or args more than once.")
        }
        return Entry(
            start: table.start, bodyStart: table.bodyStart, end: end,
            insertedSeparator: table.insertedSeparator,
            command: commands.first, args: arguments.first,
            commandValue: commands.first.flatMap { stringValue($0, in: document) }
        )
    }

    private static func stringValue(
        _ assignment: AgentTOMLScanner.Assignment, in document: AgentTOMLScanner.Document
    ) -> String? {
        var cursor = assignment.valueStart
        return AgentTOMLString.read(document.bytes, at: &cursor)
    }

    /// True when the assignment creates `mcp_servers.erst` through dotted keys or an
    /// inline table, or replaces `mcp_servers` itself, so a new table header would conflict.
    private static func declaresErst(
        _ assignment: AgentTOMLScanner.Assignment, in document: AgentTOMLScanner.Document
    ) -> Bool {
        let tablePath = assignment.tableIndex >= 0 ? document.tables[assignment.tableIndex].keys : []
        if tablePath.starts(with: ["mcp_servers", "erst"]) { return false }
        let path = tablePath + assignment.keys
        guard path.first == "mcp_servers" else { return false }
        if path == ["mcp_servers"] { return true }
        return path.count >= 2 && path[1] == "erst"
    }

    private static func unsupported(_ file: URL) -> AgentClientError {
        .invalidConfiguration(
            file: file,
            reason:
                "The mcp_servers entry uses dotted keys, an inline table, or an array of tables. "
                + "Erst cannot change that form safely. Edit the Erst entry by hand."
        )
    }
}
