import Foundation

/// JSON edits preserve other values, but pretty printing and sorting can change whitespace and key order.
struct AgentJSONConfiguration {
    private let file: URL
    private var document: [String: Any]
    private var servers: [String: Any]

    init(content: Data?, file: URL) throws {
        self.file = file
        if let content {
            do {
                guard let document = try JSONSerialization.jsonObject(with: content) as? [String: Any] else {
                    throw AgentClientError.invalidConfiguration(file: file, reason: "Expected a JSON object.")
                }
                self.document = document
            } catch let error as AgentClientError {
                throw error
            } catch {
                throw AgentClientError.invalidConfiguration(file: file, reason: error.localizedDescription)
            }
        } else {
            document = [:]
        }
        if let existing = document["mcpServers"] {
            guard let servers = existing as? [String: Any] else {
                throw AgentClientError.invalidConfiguration(
                    file: file, reason: "mcpServers must be an object.")
            }
            self.servers = servers
        } else {
            servers = [:]
        }
    }

    func isConnected(command: String) -> Bool {
        (servers["erst"] as? [String: Any])?["command"] as? String == command
    }

    mutating func connect(command: String, arguments: [String], includesType: Bool) throws -> Data? {
        var server: [String: Any]
        if let existing = servers["erst"] {
            guard let object = existing as? [String: Any] else {
                throw AgentClientError.invalidConfiguration(
                    file: file, reason: "The Erst entry must be a JSON object.")
            }
            server = object
        } else {
            server = [:]
        }
        server["command"] = command
        server["args"] = arguments
        if includesType { server["type"] = "stdio" }
        if let existing = servers["erst"] as? [String: Any],
            NSDictionary(dictionary: existing).isEqual(to: server)
        {
            return nil
        }
        servers["erst"] = server
        document["mcpServers"] = servers
        return try encoded()
    }

    mutating func disconnect() throws -> Data? {
        guard servers.removeValue(forKey: "erst") != nil else { return nil }
        document["mcpServers"] = servers.isEmpty ? nil : servers
        return try encoded()
    }

    private func encoded() throws -> Data {
        do {
            return try JSONSerialization.data(
                withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw AgentClientError.invalidConfiguration(file: file, reason: error.localizedDescription)
        }
    }
}
