import Foundation

/// Reads the table headers and assignments of a TOML document that can declare the
/// `mcp_servers.erst` entry. It is a scanner, not a full parser: values are skipped
/// with string and bracket awareness so unrelated TOML stays untouched.
struct AgentTOMLScanner {
    struct Table {
        let start: Int
        let bodyStart: Int
        let keys: [String]
        let isArray: Bool
        let insertedSeparator: Bool
    }

    struct Assignment {
        let tableIndex: Int
        let lineStart: Int
        let keys: [String]
        let valueStart: Int
        let valueEnd: Int
        let lineEnd: Int
    }

    struct Document {
        let bytes: [UInt8]
        let bomLength: Int
        let tables: [Table]
        let assignments: [Assignment]
    }

    private static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    let bytes: [UInt8]
    let file: URL

    func scan() throws -> Document {
        let bomLength = bytes.starts(with: Self.bom) ? Self.bom.count : 0
        var cursor = bomLength
        var tables: [Table] = []
        var assignments: [Assignment] = []
        while true {
            skipBlank(&cursor)
            guard cursor < bytes.count else { break }
            if bytes[cursor] == Self.openBracket {
                tables.append(try header(&cursor))
            } else {
                assignments.append(try assignment(&cursor, tableIndex: tables.count - 1))
            }
        }
        return Document(bytes: bytes, bomLength: bomLength, tables: tables, assignments: assignments)
    }

    private func header(_ cursor: inout Int) throws -> Table {
        let start = cursor
        cursor += 1
        let isArray = cursor < bytes.count && bytes[cursor] == Self.openBracket
        if isArray { cursor += 1 }
        let keys = try keyPath(&cursor)
        skipSpace(&cursor)
        guard cursor < bytes.count, bytes[cursor] == Self.closeBracket else {
            throw invalid("Could not read a TOML table header.")
        }
        cursor += 1
        if isArray {
            guard cursor < bytes.count, bytes[cursor] == Self.closeBracket else {
                throw invalid("Could not read a TOML table header.")
            }
            cursor += 1
        }
        let suffixStart = cursor
        let lineEnd = bytes[cursor...].firstIndex(of: Self.lineFeed) ?? bytes.count
        let suffix = String(decoding: bytes[suffixStart..<lineEnd], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyStart = try finishLine(&cursor)
        return Table(
            start: start, bodyStart: bodyStart, keys: keys, isArray: isArray,
            insertedSeparator: suffix == AgentTOMLConfiguration.separatorComment
        )
    }

    private func assignment(_ cursor: inout Int, tableIndex: Int) throws -> Assignment {
        let lineStart = cursor
        let keys = try keyPath(&cursor)
        skipSpace(&cursor)
        guard cursor < bytes.count, bytes[cursor] == Self.equals else {
            throw invalid("Could not read a TOML assignment.")
        }
        cursor += 1
        skipSpace(&cursor)
        let valueStart = cursor
        try skipValue(&cursor)
        let valueEnd = cursor
        let lineEnd = try finishLine(&cursor)
        return Assignment(
            tableIndex: tableIndex, lineStart: lineStart, keys: keys, valueStart: valueStart,
            valueEnd: valueEnd, lineEnd: lineEnd
        )
    }

    private func keyPath(_ cursor: inout Int) throws -> [String] {
        var keys: [String] = []
        while true {
            skipSpace(&cursor)
            guard let key = key(&cursor) else {
                throw invalid("Could not read a TOML key.")
            }
            keys.append(key)
            skipSpace(&cursor)
            guard cursor < bytes.count, bytes[cursor] == Self.dot else { return keys }
            cursor += 1
        }
    }

    private func key(_ cursor: inout Int) -> String? {
        guard cursor < bytes.count else { return nil }
        let byte = bytes[cursor]
        if byte == Self.doubleQuote || byte == Self.singleQuote {
            guard !bytes.dropFirst(cursor).prefix(3).elementsEqual([byte, byte, byte]) else {
                return nil
            }
            return AgentTOMLString.read(bytes, at: &cursor)
        }
        let start = cursor
        while cursor < bytes.count {
            let byte = bytes[cursor]
            guard
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                    || byte == Self.hyphen || byte == Self.underscore
            else { break }
            cursor += 1
        }
        return cursor == start ? nil : String(decoding: bytes[start..<cursor], as: UTF8.self)
    }

    private func skipValue(_ cursor: inout Int) throws {
        guard cursor < bytes.count else { throw invalid("Missing TOML value.") }
        switch bytes[cursor] {
        case Self.doubleQuote, Self.singleQuote:
            guard AgentTOMLString.read(bytes, at: &cursor) != nil else {
                throw invalid("Could not read a TOML string.")
            }
        case Self.openBracket:
            try skipArray(&cursor)
        case Self.openBrace:
            try skipInlineTable(&cursor)
        default:
            let start = cursor
            while cursor < bytes.count, !Self.endsBareValue(bytes[cursor]) {
                cursor += 1
            }
            while cursor > start, Self.isSpace(bytes[cursor - 1]) { cursor -= 1 }
            guard cursor > start else { throw invalid("Missing TOML value.") }
        }
    }

    private func skipArray(_ cursor: inout Int) throws {
        cursor += 1
        while true {
            skipBlank(&cursor)
            guard cursor < bytes.count else { throw invalid("Unbalanced TOML brackets.") }
            if bytes[cursor] == Self.closeBracket {
                cursor += 1
                return
            }
            try skipValue(&cursor)
            skipBlank(&cursor)
            guard cursor < bytes.count else { throw invalid("Unbalanced TOML brackets.") }
            if bytes[cursor] == Self.comma {
                cursor += 1
                continue
            }
            if bytes[cursor] == Self.closeBracket {
                cursor += 1
                return
            }
            throw invalid("Could not read a TOML array.")
        }
    }

    private func skipInlineTable(_ cursor: inout Int) throws {
        cursor += 1
        while true {
            skipBlank(&cursor)
            guard cursor < bytes.count else { throw invalid("Unbalanced TOML brackets.") }
            if bytes[cursor] == Self.closeBrace {
                cursor += 1
                return
            }
            _ = try keyPath(&cursor)
            skipSpace(&cursor)
            guard cursor < bytes.count, bytes[cursor] == Self.equals else {
                throw invalid("Could not read a TOML inline table.")
            }
            cursor += 1
            skipSpace(&cursor)
            try skipValue(&cursor)
            skipBlank(&cursor)
            guard cursor < bytes.count else { throw invalid("Unbalanced TOML brackets.") }
            if bytes[cursor] == Self.comma {
                cursor += 1
                continue
            }
            if bytes[cursor] == Self.closeBrace {
                cursor += 1
                return
            }
            throw invalid("Could not read a TOML inline table.")
        }
    }

    private func finishLine(_ cursor: inout Int) throws -> Int {
        while cursor < bytes.count, Self.isSpace(bytes[cursor]) { cursor += 1 }
        if cursor < bytes.count, bytes[cursor] == Self.hash {
            while cursor < bytes.count, bytes[cursor] != Self.lineFeed { cursor += 1 }
        }
        guard cursor < bytes.count else { return cursor }
        guard bytes[cursor] == Self.lineFeed else {
            throw invalid("Unexpected text after a TOML value.")
        }
        cursor += 1
        return cursor
    }

    private func skipBlank(_ cursor: inout Int) {
        while cursor < bytes.count {
            switch bytes[cursor] {
            case Self.lineFeed, Self.carriageReturn, Self.tab, Self.space:
                cursor += 1
            case Self.hash:
                while cursor < bytes.count, bytes[cursor] != Self.lineFeed { cursor += 1 }
            default:
                return
            }
        }
    }

    private func skipSpace(_ cursor: inout Int) {
        while cursor < bytes.count, bytes[cursor] == Self.tab || bytes[cursor] == Self.space {
            cursor += 1
        }
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 9 || byte == 13 || byte == 32
    }

    private static func endsBareValue(_ byte: UInt8) -> Bool {
        byte == lineFeed || byte == hash || byte == comma || byte == closeBracket || byte == closeBrace
    }

    private func invalid(_ reason: String) -> AgentClientError {
        .invalidConfiguration(file: file, reason: reason)
    }

    private static let tab: UInt8 = 9
    private static let lineFeed: UInt8 = 10
    private static let carriageReturn: UInt8 = 13
    private static let space: UInt8 = 32
    private static let hash: UInt8 = 35
    private static let singleQuote: UInt8 = 39
    private static let openBrace: UInt8 = 123
    private static let closeBrace: UInt8 = 125
    private static let comma: UInt8 = 44
    private static let hyphen: UInt8 = 45
    private static let dot: UInt8 = 46
    private static let equals: UInt8 = 61
    private static let openBracket: UInt8 = 91
    private static let closeBracket: UInt8 = 93
    private static let underscore: UInt8 = 95
    private static let doubleQuote: UInt8 = 34
}
