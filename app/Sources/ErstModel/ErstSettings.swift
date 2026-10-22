import Foundation

/// Everything the capture engine and the retention policy read from settings.
public struct ErstSettings: Codable, Hashable, Sendable {
    /// How much CPU the encoder may spend for smaller files.
    public enum Compression: String, Codable, CaseIterable, Hashable, Sendable {
        case faster
        case smaller

        public var title: String {
            switch self {
            case .faster: "Faster"
            case .smaller: "Smaller"
            }
        }
    }

    /// What happens after the lighter copy expires.
    public enum AfterLighterCopy: String, Codable, CaseIterable, Hashable, Sendable {
        case keepText
        case deleteEverything

        public var title: String {
            switch self {
            case .keepText: "Keep the text"
            case .deleteEverything: "Delete everything"
            }
        }
    }

    public static let captureIntervalChoices = [1, 2, 5, 10]
    public static let fullQualityDayChoices = [3, 7, 14, 30]
    public static let lighterCopyMonthChoices: [Int?] = [1, 3, 6, 12, nil]
    public static let storageLimitChoices: [Int?] = [5, 10, 20, 50, nil]
    public static let agentHistoryChoices: [Int?] = [1, 7, 30, 90, nil]

    public var isRecording: Bool
    public var launchAtLogin: Bool
    public var captureIntervalSeconds: Int
    public var compression: Compression
    public var fullQualityDays: Int
    /// Number of months the lighter copy is kept. `nil` keeps it forever.
    public var lighterCopyMonths: Int?
    public var afterLighterCopy: AfterLighterCopy
    /// Storage cap in gigabytes. `nil` means no limit.
    public var storageLimitGigabytes: Int?
    public var excludedApps: [AppRef]
    /// How far back agents may read. `nil` means all history.
    public var agentHistoryDays: Int?

    public init(
        isRecording: Bool,
        launchAtLogin: Bool,
        captureIntervalSeconds: Int,
        compression: Compression,
        fullQualityDays: Int,
        lighterCopyMonths: Int?,
        afterLighterCopy: AfterLighterCopy,
        storageLimitGigabytes: Int?,
        excludedApps: [AppRef],
        agentHistoryDays: Int?
    ) {
        self.isRecording = isRecording
        self.launchAtLogin = launchAtLogin
        self.captureIntervalSeconds = captureIntervalSeconds
        self.compression = compression
        self.fullQualityDays = fullQualityDays
        self.lighterCopyMonths = lighterCopyMonths
        self.afterLighterCopy = afterLighterCopy
        self.storageLimitGigabytes = storageLimitGigabytes
        self.excludedApps = excludedApps
        self.agentHistoryDays = agentHistoryDays
    }

    public static let `default` = ErstSettings(
        isRecording: true,
        launchAtLogin: true,
        captureIntervalSeconds: 2,
        compression: .smaller,
        fullQualityDays: 7,
        lighterCopyMonths: 3,
        afterLighterCopy: .keepText,
        storageLimitGigabytes: 20,
        excludedApps: [AppRef(bundleID: "com.1password.1password", name: "1Password")],
        agentHistoryDays: 7
    )

    private enum CodingKeys: String, CodingKey {
        case isRecording
        case launchAtLogin
        case captureIntervalSeconds
        case compression
        case fullQualityDays
        case lighterCopyMonths
        case afterLighterCopy
        case storageLimitGigabytes
        case excludedApps
        case agentHistoryDays
    }

    /// Older builds stored keys that no longer exist. Missing values fall back to the defaults.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ErstSettings.default
        isRecording = try container.decodeIfPresent(Bool.self, forKey: .isRecording) ?? fallback.isRecording
        launchAtLogin =
            try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin
        captureIntervalSeconds =
            try container.decodeIfPresent(Int.self, forKey: .captureIntervalSeconds)
            ?? fallback.captureIntervalSeconds
        compression =
            try container.decodeIfPresent(Compression.self, forKey: .compression) ?? fallback.compression
        fullQualityDays =
            try container.decodeIfPresent(Int.self, forKey: .fullQualityDays) ?? fallback.fullQualityDays
        lighterCopyMonths =
            container.contains(.lighterCopyMonths)
            ? try container.decodeIfPresent(Int.self, forKey: .lighterCopyMonths)
            : fallback.lighterCopyMonths
        if let raw = try container.decodeIfPresent(String.self, forKey: .afterLighterCopy) {
            afterLighterCopy =
                AfterLighterCopy(rawValue: raw)
                ?? (raw == "delete" ? .deleteEverything : .keepText)
        } else {
            afterLighterCopy = fallback.afterLighterCopy
        }
        storageLimitGigabytes =
            container.contains(.storageLimitGigabytes)
            ? try container.decodeIfPresent(Int.self, forKey: .storageLimitGigabytes)
            : fallback.storageLimitGigabytes
        excludedApps =
            try container.decodeIfPresent([AppRef].self, forKey: .excludedApps) ?? fallback.excludedApps
        agentHistoryDays =
            container.contains(.agentHistoryDays)
            ? try container.decodeIfPresent(Int.self, forKey: .agentHistoryDays)
            : fallback.agentHistoryDays
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isRecording, forKey: .isRecording)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(captureIntervalSeconds, forKey: .captureIntervalSeconds)
        try container.encode(compression, forKey: .compression)
        try container.encode(fullQualityDays, forKey: .fullQualityDays)
        // Explicit nulls distinguish an unlimited choice from a missing key in an older document.
        try container.encode(lighterCopyMonths, forKey: .lighterCopyMonths)
        try container.encode(afterLighterCopy, forKey: .afterLighterCopy)
        try container.encode(storageLimitGigabytes, forKey: .storageLimitGigabytes)
        try container.encode(excludedApps, forKey: .excludedApps)
        try container.encode(agentHistoryDays, forKey: .agentHistoryDays)
    }
}
