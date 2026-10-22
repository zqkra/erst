import ErstKit
import ErstModel
import Foundation

/// The recorder configuration the app builds from its saved settings.
///
/// Mirrors `FfiConversions.configuration(_:)` in
/// `app/Sources/ErstKit/Live/FfiConversions.swift` (line 152), which is internal to
/// ErstKit. That function sets only the capture interval, compression, and excluded apps,
/// so the segment duration and idle threshold keep `RecorderConfiguration`'s defaults.
/// The values come from `ErstSettings.default` in
/// `app/Sources/ErstModel/ErstSettings.swift` (line 75).
enum ProbeProductionConfiguration {
    /// One year, used only when `--no-idle-gate` asks the probe to keep capturing without input.
    static let disabledIdleThreshold: TimeInterval = 365 * 24 * 60 * 60

    static func make() -> RecorderConfiguration {
        let settings = ErstSettings.default
        return RecorderConfiguration(
            captureInterval: Double(settings.captureIntervalSeconds),
            compression: settings.compression == .faster ? .faster : .smaller,
            excludedBundleIDs: Set(settings.excludedApps.map(\.bundleID))
        )
    }

    static func disablingIdleGate(_ configuration: RecorderConfiguration) -> RecorderConfiguration {
        var configuration = configuration
        configuration.idleThreshold = disabledIdleThreshold
        return configuration
    }
}
