import ErstModel
import Foundation

enum PreviewApps {
    static let mail = AppRef(bundleID: "com.apple.mail", name: "Mail")
    static let slack = AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    static let safari = AppRef(bundleID: "com.apple.Safari", name: "Safari")
    static let ghostty = AppRef(bundleID: "com.mitchellh.ghostty", name: "Ghostty")
    static let zed = AppRef(bundleID: "dev.zed.Zed", name: "Zed")
    static let x = AppRef(bundleID: "com.twitter.twitter-mac", name: "X")
}

struct PreviewSpan: Sendable {
    let id: Int64
    let app: AppRef
    let windowTitle: String
    let url: URL?
    let range: ClosedRange<Date>
    let screen: PreviewScreen
}

struct PreviewMomentRecord: Sendable {
    let moment: Moment
    let lines: [TextLine]
    let span: PreviewSpan
    let image: URL
}

/// A developer's weekday, repeated with small shifts for earlier days: an open source tool goes
/// around the team, from a post on X to the project's CI. In the afternoon the six apps that mention
/// it come back once each, so searching "open source" finds one moment in each.
enum PreviewSchedule {
    private struct Template {
        let app: AppRef
        let title: String
        let url: URL?
        let startMinute: Int
        let endMinute: Int
        let screen: PreviewScreen
    }

    private static let repositoryURL = URL(string: "https://github.com/brisk-dev/brisk")
    private static let repositoryTitle = "GitHub - brisk-dev/brisk: Fast, open source test selection"
    private static let talkURL = URL(string: "https://www.youtube.com/watch?v=Mz1oNotFloat")
    private static let talkTitle =
        "Money is not a float: rounding, currencies, and the bugs we ship - YouTube"
    private static let docsURL = URL(
        string:
            "https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/NumberFormat"
    )
    private static let docsTitle = "Intl.NumberFormat - JavaScript | MDN"
    private static let channelTitle = "web-team (Channel) - Fernwood - Slack"
    private static let terminalTitle = "~/code/fernwood/web"

    private static let templates: [Template] = [
        Template(
            app: PreviewApps.mail, title: "Inbox", url: nil, startMinute: 488, endMinute: 512,
            screen: .mail
        ),
        Template(
            app: PreviewApps.slack, title: channelTitle, url: nil, startMinute: 512, endMinute: 548,
            screen: .slack
        ),
        Template(
            app: PreviewApps.zed, title: "dependencies.md", url: nil, startMinute: 548, endMinute: 600,
            screen: .zed
        ),
        Template(
            app: PreviewApps.ghostty, title: terminalTitle, url: nil, startMinute: 600, endMinute: 624,
            screen: .ghostty
        ),
        Template(
            app: PreviewApps.safari, title: repositoryTitle, url: repositoryURL, startMinute: 624,
            endMinute: 660,
            screen: .github
        ),
        Template(
            app: PreviewApps.zed, title: "dependencies.md", url: nil, startMinute: 660, endMinute: 704,
            screen: .zed
        ),
        Template(
            app: PreviewApps.x, title: "Home / X", url: nil, startMinute: 704, endMinute: 722,
            screen: .x
        ),
        // A lunch break long enough to start a new timeline session.
        Template(
            app: PreviewApps.safari, title: talkTitle, url: talkURL, startMinute: 760, endMinute: 792,
            screen: .youtube
        ),
        Template(
            app: PreviewApps.safari, title: docsTitle, url: docsURL, startMinute: 792, endMinute: 826,
            screen: .docs
        ),
        Template(
            app: PreviewApps.zed, title: "dependencies.md", url: nil, startMinute: 826, endMinute: 872,
            screen: .zed
        ),
        Template(
            app: PreviewApps.slack, title: channelTitle, url: nil, startMinute: 872, endMinute: 898,
            screen: .slack
        ),
        Template(
            app: PreviewApps.ghostty, title: terminalTitle, url: nil, startMinute: 898, endMinute: 930,
            screen: .ghostty
        ),
        Template(
            app: PreviewApps.safari, title: repositoryTitle, url: repositoryURL, startMinute: 930,
            endMinute: 962,
            screen: .github
        ),
        Template(
            app: PreviewApps.mail, title: "Inbox", url: nil, startMinute: 962, endMinute: 982,
            screen: .mail
        ),
        Template(
            app: PreviewApps.x, title: "Home / X", url: nil, startMinute: 982, endMinute: 1010,
            screen: .x
        ),
        Template(
            app: PreviewApps.zed, title: "dependencies.md", url: nil, startMinute: 1010, endMinute: 1092,
            screen: .zed
        ),
    ]

    static func spans(dayOffset: Int, today: Date, now: Date) -> [PreviewSpan] {
        let calendar = Calendar.current
        guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: today) else { return [] }
        let weekday = calendar.component(.weekday, from: dayStart)
        let isWeekend = weekday == 1 || weekday == 7
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        var result: [PreviewSpan] = []
        for (index, template) in templates.enumerated() {
            if dayOffset != 0 {
                if (abs(dayOffset) + index) % 7 == 0 { continue }
                if isWeekend && index % 3 == 1 { continue }
            }
            let shift = dayOffset == 0 ? 0 : ((abs(dayOffset) * 5 + index * 3) % 13) - 6
            let startMinutes = template.startMinute + shift
            let endMinutes = template.endMinute + shift
            guard let start = calendar.date(byAdding: .minute, value: startMinutes, to: dayStart) else {
                continue
            }
            var end = calendar.date(byAdding: .minute, value: endMinutes, to: dayStart) ?? start
            if dayOffset == 0 {
                end = min(end, now)
            } else {
                end = min(end, dayEnd)
            }
            guard start < end else { continue }
            let identifier = Int64((dayOffset + 100) * 100_000 + index * 100)
            result.append(
                PreviewSpan(
                    id: identifier,
                    app: template.app,
                    windowTitle: template.title,
                    url: template.url,
                    range: start...end,
                    screen: template.screen
                )
            )
        }
        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func moments(spans: [PreviewSpan]) -> [PreviewMomentRecord] {
        var records: [PreviewMomentRecord] = []
        for (spanIndex, span) in spans.enumerated() {
            let interval = momentInterval(span.screen)
            var times: [Date] = []
            var capturedAt = span.range.lowerBound.addingTimeInterval(interval)
            while capturedAt < span.range.upperBound.addingTimeInterval(-30) {
                precondition(times.count < 99, "A preview span holds at most 99 moments")
                times.append(capturedAt)
                capturedAt = capturedAt.addingTimeInterval(
                    captureRhythm[(spanIndex + times.count) % captureRhythm.count] * interval / 60)
            }
            // The window moves on during a visit, so a later moment shows a later variant.
            let variants = PreviewScreens.variants(of: span.screen)
            for (momentIndex, capturedAt) in times.enumerated() {
                let variant = variants[momentIndex * variants.count / times.count]
                let moment = Moment(
                    id: span.id + Int64(momentIndex + 1),
                    capturedAt: capturedAt,
                    app: span.app,
                    windowTitle: span.windowTitle,
                    url: span.url
                )
                records.append(
                    PreviewMomentRecord(
                        moment: moment, lines: variant.lines, span: span, image: variant.image))
            }
        }
        return records
    }

    /// Seconds between captures, cycled inside a span: a burst, a pause, a slow read, a burst.
    /// The mean is close to a minute, scaled per screen by `momentInterval / 60`.
    private static let captureRhythm: [TimeInterval] = [
        8, 8, 8, 8, 8, 8, 45, 90, 180, 120, 25, 10, 6, 196,
    ]

    private static func momentInterval(_ screen: PreviewScreen) -> TimeInterval {
        switch screen {
        case .ghostty: 45
        case .zed, .slack, .x: 60
        case .mail, .github: 75
        case .docs: 90
        case .youtube: 120
        }
    }
}
