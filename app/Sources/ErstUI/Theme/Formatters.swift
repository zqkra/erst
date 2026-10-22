import Foundation

/// Locale-stable strings so screenshots and the interface read the same.
@MainActor
public enum ErstFormat {
    private static let secondsPerMinute: TimeInterval = 60
    private static let minutesPerHour = 60
    private static let bytesPerKilobyte = 1_000.0
    private static let bytesPerMegabyte = 1_000_000.0
    private static let bytesPerGigabyte = 1_000_000_000.0
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let shortClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEEE, d MMM"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    public static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    public static func shortClock(_ date: Date) -> String {
        shortClockFormatter.string(from: date)
    }

    public static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    public static func month(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    public static func weekdayShort(_ weekday: Int) -> String {
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return symbols[(weekday - 1 + symbols.count) % symbols.count]
    }

    public static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    public static func relativeDay(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today \(shortClock(date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(shortClock(date))"
        }
        return "\(shortDate(date)) \(shortClock(date))"
    }

    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / secondsPerMinute).rounded()))
        let hours = minutes / minutesPerHour
        let remainder = minutes % minutesPerHour
        if hours > 0 && remainder > 0 {
            return "\(hours)h \(remainder)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainder)m"
    }

    public static func bytes(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= bytesPerGigabyte {
            return "\(compact(value / bytesPerGigabyte)) GB"
        }
        if value >= bytesPerMegabyte {
            return "\(compact(value / bytesPerMegabyte)) MB"
        }
        if value >= bytesPerKilobyte {
            return "\(compact(value / bytesPerKilobyte)) KB"
        }
        return "\(bytes) B"
    }

    private static func compact(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
