import Foundation

/// Heat levels for the timeline track, one per frame, from 0 (quiet) to 5 (busy).
///
/// A frame's activity is the weighted count of kept frames captured within `windowSeconds`
/// of it, itself included. Each frame weighs `min(1, changeRatio * 20)`, the weight the menu
/// bar heat gives a frame, so a frame kept only because the maximum gap passed adds little.
/// The keep policy holds continuous motion to about one frame per 10 seconds, so a busy
/// minute reaches about 6. Fixed thresholds keep a frame's level stable when more history loads.
public enum TrackHeat {
    /// Seconds on each side of a frame that count toward its activity.
    public static let windowSeconds: TimeInterval = 30
    /// Lower bounds of levels 1 through 5.
    public static let thresholds: [Double] = [1, 2, 3, 4.5, 6]
    /// The change ratio at which a frame counts fully, as in the menu bar heat.
    static let fullWeightRatio = 0.05

    /// Levels for frames sorted by capture time, in one pass with two moving bounds.
    public static func levels(for frames: [TrackFrame]) -> [UInt8] {
        var prefix = [Double](repeating: 0, count: frames.count + 1)
        for (index, frame) in frames.enumerated() {
            prefix[index + 1] = prefix[index] + min(1, max(0, frame.changeRatio) / fullWeightRatio)
        }
        var levels = [UInt8](repeating: 0, count: frames.count)
        var lower = 0
        var upper = 0
        for index in frames.indices {
            let center = frames[index].capturedAt
            while frames[lower].capturedAt < center.addingTimeInterval(-windowSeconds) { lower += 1 }
            while upper < frames.count, frames[upper].capturedAt <= center.addingTimeInterval(windowSeconds) {
                upper += 1
            }
            let activity = prefix[upper] - prefix[lower]
            levels[index] = UInt8(thresholds.lastIndex { activity >= $0 }.map { $0 + 1 } ?? 0)
        }
        return levels
    }
}
