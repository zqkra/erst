import ErstModel
import Foundation

enum SearchSyntax {
    /// Encodes the filters as query text the engine resolves in `timeZone`, the same zone it is given.
    static func encode(_ query: SearchQuery, in timeZone: TimeZone) -> String {
        var parts = [query.text]
        if let app = query.app { parts.append("app:\(app.bundleID)") }
        if let range = query.range {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let format = DateFormatter()
            format.calendar = calendar
            format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = timeZone
            format.dateFormat = "yyyy-MM-dd"
            parts.append("since:\(format.string(from: range.lowerBound))")
            // The parser includes the entire until day. UI date ranges end at the next midnight.
            let upper = range.upperBound
            let until =
                upper == calendar.startOfDay(for: upper) && upper > range.lowerBound
                ? upper.addingTimeInterval(-0.001) : upper
            parts.append("until:\(format.string(from: until))")
        }
        return parts.joined(separator: " ")
    }
}
