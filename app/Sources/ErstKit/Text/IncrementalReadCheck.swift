import Foundation

/// Reads a frame both ways, whole and only where it changed since a previous frame, so ErstProbe
/// can prove the incremental read keeps every word and measure what it saves.
public enum IncrementalReadCheck {
    public struct Outcome: Sendable {
        /// The previous frame read whole: the text the incremental read keeps where nothing changed.
        public let previous: [RecognizedLine]
        public let whole: [RecognizedLine]
        public let incremental: [RecognizedLine]
        /// Regions read again, or nil when the plan read the whole frame.
        public let regionCount: Int?
        public let wholeMilliseconds: Double
        /// Includes fingerprinting the frame and planning the read.
        public let incrementalMilliseconds: Double
    }

    public static func compare(
        previous: CapturedFrame, current: CapturedFrame
    ) async throws -> Outcome {
        let recognizer = TextRecognizer()
        let previousLines = try await recognizer.recognizeText(in: previous.pixelBuffer)
        let wholeStart = ContinuousClock.now
        let whole = try await recognizer.recognizeText(in: current.pixelBuffer)
        let wholeMilliseconds = wholeStart.duration(to: .now) / .milliseconds(1)

        let incrementalStart = ContinuousClock.now
        var plan: ReadPlan?
        if let before = TileSignature(previous.pixelBuffer), let after = TileSignature(current.pixelBuffer),
            let changed = after.changedTiles(since: before)
        {
            plan = ReadPlan.make(changed: changed, signature: after, previousLines: previousLines)
        }
        let incremental: [RecognizedLine]
        if let plan {
            let read =
                plan.regions.isEmpty
                ? []
                : try await recognizer.recognizeText(
                    in: current.pixelBuffer, regions: plan.regions.map(\.read))
            incremental = plan.merge(previous: previousLines, recognized: read)
        } else {
            incremental = try await recognizer.recognizeText(in: current.pixelBuffer)
        }
        return Outcome(
            previous: previousLines, whole: whole, incremental: incremental, regionCount: plan?.regions.count,
            wholeMilliseconds: wholeMilliseconds,
            incrementalMilliseconds: incrementalStart.duration(to: .now) / .milliseconds(1))
    }
}
