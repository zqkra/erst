import Foundation
import Vision

/// Picks Vision's recognition level for each request and falls back when the accurate model
/// cannot run.
///
/// Accurate recognition runs on the Neural Engine. When the host's Neural Engine runtime fails
/// (`e5rtError` code 13, surfaced as `CRImageReaderError`), every accurate request fails after
/// about 27 seconds, while fast recognition still reads a 1440p frame in about 180 ms. One
/// failure switches recognition to fast, and accurate is tried again after the retry interval.
struct RecognitionLevelPolicy: Sendable {
    /// What a recognition result changed, so the caller logs each switch once.
    enum Transition: Equatable, Sendable {
        case unchanged
        case fellBack
        case stayedFast
        case recovered
    }

    /// A failed accurate request costs about 4 s of CPU, so a 30 minute interval keeps the
    /// retries near 0.2% of one core.
    static let accurateRetryInterval = Duration.seconds(30 * 60)

    private var fastUntil: ContinuousClock.Instant?

    /// The level for a request that starts now.
    func level(at now: ContinuousClock.Instant) -> VNRequestTextRecognitionLevel {
        if let fastUntil, now < fastUntil { return .fast }
        return .accurate
    }

    /// Records a failed accurate request and starts or extends the fast window.
    mutating func accurateFailed(at now: ContinuousClock.Instant) -> Transition {
        let wasFast = fastUntil != nil
        fastUntil = now.advanced(by: Self.accurateRetryInterval)
        return wasFast ? .stayedFast : .fellBack
    }

    /// Records a successful accurate request and ends the fast window.
    mutating func accurateSucceeded() -> Transition {
        guard fastUntil != nil else { return .unchanged }
        fastUntil = nil
        return .recovered
    }
}
