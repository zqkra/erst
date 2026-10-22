import Foundation

/// Disk usage broken down the way the storage settings screen explains it.
public struct StorageReport: Hashable, Sendable {
    public let usedBytes: Int64
    public let limitBytes: Int64?
    public let screensBytes: Int64
    public let textBytes: Int64
    public let previewsBytes: Int64
    public let averagePerDayBytes: Int64
    public let keptTodayBytes: Int64

    public init(
        usedBytes: Int64,
        limitBytes: Int64?,
        screensBytes: Int64,
        textBytes: Int64,
        previewsBytes: Int64,
        averagePerDayBytes: Int64,
        keptTodayBytes: Int64
    ) {
        self.usedBytes = usedBytes
        self.limitBytes = limitBytes
        self.screensBytes = screensBytes
        self.textBytes = textBytes
        self.previewsBytes = previewsBytes
        self.averagePerDayBytes = averagePerDayBytes
        self.keptTodayBytes = keptTodayBytes
    }
}
