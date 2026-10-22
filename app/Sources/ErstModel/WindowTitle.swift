import Foundation

/// Window titles as people read them: without the app name that many apps append.
public enum WindowTitle {
    /// Separators apps put between a document and their own name: hyphen, en dash, em dash, middle dot, pipe.
    private static let separators = [" - ", " \u{2013} ", " \u{2014} ", " \u{00B7} ", " | "]

    /// The title without a trailing separator and app name, or nil when nothing else is left.
    public static func clean(_ title: String?, appName: String) -> String? {
        guard var text = title?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        for separator in separators {
            let suffix = separator + appName
            guard
                let ending = text.range(
                    of: suffix, options: [.caseInsensitive, .anchored, .backwards])
            else { continue }
            text.removeSubrange(ending)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        guard !text.isEmpty, text.caseInsensitiveCompare(appName) != .orderedSame else {
            return nil
        }
        return text
    }
}
