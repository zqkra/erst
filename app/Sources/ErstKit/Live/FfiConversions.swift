import CoreGraphics
import ErstCore
import ErstModel
import Foundation

enum FfiConversions {
    static let millisecondsPerSecond = 1000.0
    static let boxScale = 10_000.0

    static func date(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / millisecondsPerSecond)
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * millisecondsPerSecond).rounded())
    }

    /// The IANA name the engine resolves local days with, read at call time.
    static var timeZoneIdentifier: String { TimeZone.current.identifier }

    static func range(_ start: Int64, _ end: Int64) -> ClosedRange<Date> {
        date(start)...date(max(start, end))
    }

    static func moment(_ value: FfiMoment) -> Moment {
        Moment(
            id: value.stamp.id, capturedAt: date(value.stamp.capturedAtMs),
            app: AppRef(bundleID: value.bundleId, name: value.appName),
            windowTitle: value.windowTitle, url: value.url.flatMap(URL.init(string:)))
    }

    static func line(_ value: FfiTextLine) -> TextLine {
        TextLine(
            text: value.text,
            box: CGRect(
                x: Double(value.x) / boxScale, y: Double(value.y) / boxScale,
                width: Double(value.w) / boxScale, height: Double(value.h) / boxScale))
    }

    static func hit(_ value: FfiSearchHit) -> SearchHit {
        SearchHit(
            moment: Moment(
                id: value.frameId, capturedAt: date(value.capturedAtMs),
                app: AppRef(bundleID: value.bundleId, name: value.appName),
                windowTitle: value.windowTitle, url: value.url.flatMap(URL.init(string:))),
            matchedLines: value.matchedLines.map(line),
            firstSeen: date(value.firstSeenMs), lastSeen: date(value.lastSeenMs))
    }

    static func timeline(_ value: FfiTimeline) -> TimelineSlice {
        TimelineSlice(
            range: range(value.startMs, value.endMs), heat: Array(value.heat),
            segments: value.spans.map {
                AppSegment(
                    id: $0.id, app: AppRef(bundleID: $0.bundleId, name: $0.appName),
                    windowTitle: $0.windowTitle,
                    range: range(
                        max(value.startMs, $0.startedAtMs), min(value.endMs, $0.endedAtMs ?? value.endMs)))
            },
            moments: value.stamps.map { MomentStamp(id: $0.id, capturedAt: date($0.capturedAtMs)) })
    }

    static func track(_ value: FfiTrack) -> TimelineTrack {
        TimelineTrack(
            range: range(value.startMs, value.endMs),
            frames: value.frames.map {
                TrackFrame(
                    id: $0.id, capturedAt: date($0.capturedAtMs),
                    changeRatio: Double($0.changeRatio), segment: Int($0.segment))
            },
            segments: value.segments.enumerated().map { index, segment in
                TrackSegment(
                    id: index,
                    app: AppRef(bundleID: segment.bundleId, name: segment.appName),
                    host: segment.host,
                    title: segment.title,
                    frames: Int(segment.firstFrame)...Int(segment.lastFrame),
                    range: range(segment.startedAtMs, segment.endedAtMs),
                    startsSession: segment.startsSession)
            })
    }

    static func category(_ value: FfiCategory) -> ActivityCategory {
        switch value {
        case .building: .building
        case .reading: .reading
        case .talking: .talking
        case .other: .other
        }
    }

    static func appTotal(_ value: FfiAppTotal) -> AppTotal {
        AppTotal(
            app: AppRef(bundleID: value.bundleId, name: value.appName),
            duration: Double(value.ms) / millisecondsPerSecond)
    }

    static func bucketKind(_ value: FfiBucketKind) -> ActivityBucketKind {
        switch value {
        case .hour: .hour
        case .day: .day
        }
    }

    static func activity(_ value: FfiActivity) -> ActivityReport {
        ActivityReport(
            range: range(value.startMs, value.endMs), total: Double(value.totalMs) / millisecondsPerSecond,
            previousTotal: value.previousTotalMs.map { Double($0) / millisecondsPerSecond },
            categories: Dictionary(
                value.categories.map { (category($0.category), Double($0.ms) / millisecondsPerSecond) },
                uniquingKeysWith: +),
            bucketKind: bucketKind(value.bucketKind),
            buckets: value.buckets.map {
                ActivityBucket(
                    start: date($0.startMs),
                    end: date($0.endMs),
                    byCategory: [
                        .building: Double($0.buildingMs) / millisecondsPerSecond,
                        .reading: Double($0.readingMs) / millisecondsPerSecond,
                        .talking: Double($0.talkingMs) / millisecondsPerSecond,
                        .other: Double($0.otherMs) / millisecondsPerSecond,
                    ])
            },
            apps: value.apps.map(appTotal),
            websites: value.websites.map {
                SiteTotal(host: $0.host, duration: Double($0.ms) / millisecondsPerSecond)
            })
    }

    static func dayHeat(_ value: FfiDayHeat) -> DayHeat {
        DayHeat(start: date(value.startMs), end: date(value.endMs), hours: Array(value.hours))
    }

    static func today(_ value: FfiTodaySummary, range: ClosedRange<Date>) -> TodaySummary {
        TodaySummary(
            range: range, onScreen: Double(value.onScreenMs) / millisecondsPerSecond,
            keptBytes: Int64(clamping: value.keptBytes), heat: Array(value.heat),
            topApps: value.topApps.map(appTotal))
    }

    static func storage(_ value: FfiStorage, todayBytes: Int64) -> StorageReport {
        StorageReport(
            usedBytes: Int64(clamping: value.usedBytes),
            limitBytes: value.limitBytes.map { Int64(clamping: $0) },
            screensBytes: Int64(clamping: value.videoBytes), textBytes: Int64(clamping: value.databaseBytes),
            previewsBytes: 0, averagePerDayBytes: Int64(clamping: value.averagePerDayBytes),
            keptTodayBytes: todayBytes)
    }

    static func settings(_ value: FfiSettings) -> ErstSettings {
        ErstSettings(
            isRecording: value.isRecording, launchAtLogin: value.launchAtLogin,
            captureIntervalSeconds: Int(value.captureIntervalSeconds),
            compression: value.compression == .faster ? .faster : .smaller,
            fullQualityDays: Int(value.fullQualityDays),
            lighterCopyMonths: value.lighterCopyMonths.map(Int.init),
            afterLighterCopy: value.afterLighterCopy == .keepText ? .keepText : .deleteEverything,
            storageLimitGigabytes: value.storageLimitGigabytes.map(Int.init),
            excludedApps: value.excludedApps.map { AppRef(bundleID: $0.bundleId, name: $0.name) },
            agentHistoryDays: value.agentHistoryDays.map(Int.init))
    }

    static func settings(_ value: ErstSettings) -> FfiSettings {
        FfiSettings(
            isRecording: value.isRecording, launchAtLogin: value.launchAtLogin,
            captureIntervalSeconds: UInt32(clamping: value.captureIntervalSeconds),
            compression: value.compression == .faster ? .faster : .smaller,
            fullQualityDays: UInt32(clamping: value.fullQualityDays),
            lighterCopyMonths: value.lighterCopyMonths.map { UInt32(clamping: $0) },
            afterLighterCopy: value.afterLighterCopy == .keepText ? .keepText : .deleteEverything,
            storageLimitGigabytes: value.storageLimitGigabytes.map { UInt32(clamping: $0) },
            excludedApps: value.excludedApps.map { FfiAppRef(bundleId: $0.bundleID, name: $0.name) },
            agentHistoryDays: value.agentHistoryDays.map { UInt32(clamping: $0) })
    }

    static func configuration(_ settings: ErstSettings) -> RecorderConfiguration {
        RecorderConfiguration(
            captureInterval: Double(settings.captureIntervalSeconds),
            compression: settings.compression == .faster ? .faster : .smaller,
            excludedBundleIDs: Set(settings.excludedApps.map(\.bundleID)))
    }

    static func status(_ value: RecorderState.Status) -> RecorderStatus {
        switch value {
        case .recording: .recording
        case .paused(let until): .paused(until: until)
        case .needsPermission: .needsPermission
        case .stopped: .stopped
        }
    }
}
