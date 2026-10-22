import Foundation

enum AgentTOMLString {
    static func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 8: result += "\\b"
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 12: result += "\\f"
            case 13: result += "\\r"
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 0...31, 127: result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    static func read(_ bytes: [UInt8], at offset: inout Int) -> String? {
        guard offset < bytes.count, bytes[offset] == 34 || bytes[offset] == 39 else { return nil }
        let quote = bytes[offset]
        let multiline = bytes.dropFirst(offset).prefix(3).elementsEqual([quote, quote, quote])
        var cursor = offset + (multiline ? 3 : 1)
        var value: [UInt8] = []
        if multiline, cursor < bytes.count {
            if bytes[cursor] == 13, cursor + 1 < bytes.count, bytes[cursor + 1] == 10 { cursor += 1 }
            if bytes[cursor] == 10 { cursor += 1 }
        }
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if byte == quote {
                var end = cursor + 1
                while end < bytes.count, bytes[end] == quote { end += 1 }
                if !multiline || end - cursor >= 3 {
                    if multiline {
                        guard end - cursor <= 5 else { return nil }
                        value.append(contentsOf: repeatElement(quote, count: end - cursor - 3))
                    }
                    offset = multiline ? end : cursor + 1
                    return String(bytes: value, encoding: .utf8)
                }
            }
            if quote == 34, byte == 92 {
                cursor += 1
                guard appendEscape(bytes, cursor: &cursor, multiline: multiline, value: &value) else {
                    return nil
                }
                continue
            }
            guard byte >= 32 && byte != 127 || byte == 9 || multiline && (byte == 10 || byte == 13) else {
                return nil
            }
            if byte == 13 {
                guard cursor + 1 < bytes.count, bytes[cursor + 1] == 10 else { return nil }
                cursor += 1
                value.append(10)
            } else {
                value.append(byte)
            }
            cursor += 1
        }
        return nil
    }

    private static func appendEscape(
        _ bytes: [UInt8], cursor: inout Int, multiline: Bool, value: inout [UInt8]
    ) -> Bool {
        guard cursor < bytes.count else { return false }
        let escaped = bytes[cursor]
        cursor += 1
        switch escaped {
        case 34, 92: value.append(escaped)
        case 98: value.append(8)
        case 116: value.append(9)
        case 110: value.append(10)
        case 102: value.append(12)
        case 114: value.append(13)
        case 117, 85:
            let end = cursor + (escaped == 117 ? 4 : 8)
            guard end <= bytes.count,
                let number = UInt32(String(decoding: bytes[cursor..<end], as: UTF8.self), radix: 16),
                let scalar = UnicodeScalar(number)
            else { return false }
            value.append(contentsOf: String(scalar).utf8)
            cursor = end
        case 9, 10, 13, 32:
            guard multiline else { return false }
            var hasNewline = escaped == 10
            while cursor < bytes.count, [9, 10, 13, 32].contains(bytes[cursor]) {
                hasNewline = hasNewline || bytes[cursor] == 10
                cursor += 1
            }
            return hasNewline
        default: return false
        }
        return true
    }
}
