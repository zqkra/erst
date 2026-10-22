import ErstModel
import Foundation

enum PreviewApps {
    static let x = AppRef(bundleID: "com.twitter.twitter-mac", name: "X")
    static let whatsApp = AppRef(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp")
    static let safari = AppRef(bundleID: "com.apple.Safari", name: "Safari")
    static let mail = AppRef(bundleID: "com.apple.mail", name: "Mail")
    static let notes = AppRef(bundleID: "com.apple.Notes", name: "Notes")
    static let zed = AppRef(bundleID: "dev.zed.Zed", name: "Zed")
}

struct PreviewSpan: Sendable {
    let id: Int64
    let app: AppRef
    let windowTitle: String
    let url: URL?
    let range: ClosedRange<Date>
    let layout: PreviewLayout
}

struct PreviewMomentRecord: Sendable {
    let moment: Moment
    let lines: [TextLine]
    let span: PreviewSpan
}

/// A realistic weekday of app visits, repeated with small shifts for earlier days.
enum PreviewSchedule {
    private struct Template {
        let app: AppRef
        let title: String
        let url: URL?
        let startMinute: Int
        let endMinute: Int
        let layout: PreviewLayout
    }

    private static let articleURL = URL(string: "https://calm.design/notes")
    private static let pinningURL = URL(string: "https://doc.rust-lang.org/std/pin/index.html")
    private static let youtubeURL = URL(string: "https://www.youtube.com")

    private static let templates: [Template] = [
        Template(
            app: PreviewApps.mail, title: "Inbox", url: nil, startMinute: 488, endMinute: 512,
            layout: .mail
        ),
        Template(
            app: PreviewApps.safari, title: "Designing calm software", url: articleURL, startMinute: 512,
            endMinute: 554, layout: .article
        ),
        Template(
            app: PreviewApps.whatsApp, title: "Maya Chen", url: nil, startMinute: 554, endMinute: 586,
            layout: .whatsApp
        ),
        Template(
            app: PreviewApps.x, title: "Home / X", url: nil, startMinute: 586, endMinute: 628,
            layout: .xFeed
        ),
        Template(
            app: PreviewApps.safari, title: "YouTube", url: youtubeURL, startMinute: 628, endMinute: 662,
            layout: .youtube
        ),
        Template(
            app: PreviewApps.zed, title: "capture.rs", url: nil, startMinute: 662, endMinute: 704,
            layout: .editor
        ),
        // A lunch break long enough to start a new timeline session.
        Template(
            app: PreviewApps.notes, title: "Product notes", url: nil, startMinute: 734, endMinute: 758,
            layout: .notes
        ),
        Template(
            app: PreviewApps.whatsApp, title: "Design crew", url: nil, startMinute: 758, endMinute: 792,
            layout: .whatsApp
        ),
        Template(
            app: PreviewApps.mail, title: "Inbox", url: nil, startMinute: 792, endMinute: 816,
            layout: .mail
        ),
        Template(
            app: PreviewApps.safari, title: "YouTube", url: youtubeURL, startMinute: 816, endMinute: 854,
            layout: .youtube
        ),
        Template(
            app: PreviewApps.x, title: "Home / X", url: nil, startMinute: 854, endMinute: 890,
            layout: .xFeed
        ),
        Template(
            app: PreviewApps.safari, title: "Pinning in practice", url: pinningURL, startMinute: 890,
            endMinute: 934, layout: .article
        ),
        Template(
            app: PreviewApps.notes, title: "Design review", url: nil, startMinute: 934, endMinute: 968,
            layout: .notes
        ),
        Template(
            app: PreviewApps.whatsApp, title: "Design crew", url: nil, startMinute: 968, endMinute: 992,
            layout: .whatsApp
        ),
        Template(
            app: PreviewApps.zed, title: "store.rs", url: nil, startMinute: 992, endMinute: 1038,
            layout: .editor
        ),
        Template(
            app: PreviewApps.x, title: "Home / X", url: nil, startMinute: 1038, endMinute: 1092,
            layout: .xFeed
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
                    layout: template.layout
                )
            )
        }
        return result.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    static func moments(spans: [PreviewSpan]) -> [PreviewMomentRecord] {
        var records: [PreviewMomentRecord] = []
        for (spanIndex, span) in spans.enumerated() {
            let interval = momentInterval(span.layout)
            var capturedAt = span.range.lowerBound.addingTimeInterval(interval)
            var momentIndex = 0
            while capturedAt < span.range.upperBound.addingTimeInterval(-30) {
                precondition(momentIndex < 99, "A preview span holds at most 99 moments")
                let variant = spanIndex * 3 + momentIndex
                let specs = PreviewContent.lines(for: span.layout, variant: variant, title: span.windowTitle)
                let moment = Moment(
                    id: span.id + Int64(momentIndex + 1),
                    capturedAt: capturedAt,
                    app: span.app,
                    windowTitle: span.windowTitle,
                    url: span.url
                )
                records.append(
                    PreviewMomentRecord(
                        moment: moment,
                        lines: specs.map { TextLine(text: $0.text, box: $0.rect) },
                        span: span
                    )
                )
                momentIndex += 1
                capturedAt = capturedAt.addingTimeInterval(
                    captureRhythm[(spanIndex + momentIndex) % captureRhythm.count] * interval / 60)
            }
        }
        return records
    }

    /// Seconds between captures, cycled inside a span: a burst, a pause, a slow read, a burst.
    /// The mean is close to a minute, scaled per layout by `momentInterval / 60`.
    private static let captureRhythm: [TimeInterval] = [
        8, 8, 8, 8, 8, 8, 45, 90, 180, 120, 25, 10, 6, 196,
    ]

    private static func momentInterval(_ layout: PreviewLayout) -> TimeInterval {
        switch layout {
        case .xFeed: 60
        case .whatsApp: 75
        case .youtube: 120
        case .article: 90
        case .mail: 75
        case .notes: 75
        case .editor: 60
        }
    }
}
