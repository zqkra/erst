import CoreVideo
import Foundation
import Vision
import os

private let textRecognizerLog = Logger(subsystem: "app.erst.Erst", category: "TextRecognizer")
private let minimumConfidence: Float = 0.3
private let minimumTextHeightPixels: Float = 6

/// Runs Vision text recognition on kept frames. Requests use accurate recognition, and fast
/// recognition while the accurate model cannot run on this host.
///
/// It uses the classic `VNRecognizeTextRequest`, because the Swift `RecognizeTextRequest`
/// took 12 to 32 seconds per frame on the development machine.
public actor TextRecognizer {
    /// Owns the process-wide warm-up. Each request builds its own Vision request, so the models
    /// Vision loads belong to the process, and one load serves every recognizer.
    private static let warmUpOwner = TextRecognizer()
    /// Shared by every recognizer, because the Neural Engine failure is host-wide and the
    /// warm-up runs on its own recognizer.
    private static let levelPolicy = OSAllocatedUnfairLock(initialState: RecognitionLevelPolicy())

    private var warmUpTask: Task<Double, Never>?

    /// Creates a recognizer. Recognition runs on the actor's background executor.
    public init() {}

    /// Loads Vision's text models once per process and returns the load time in milliseconds.
    ///
    /// The app calls this at launch. The first accurate request after launch compiles Neural
    /// Engine models for 30 to 50 seconds. Later calls do not load again. They await the first
    /// load and return the same time.
    @discardableResult
    public static func warmUp() async -> Double {
        await warmUpOwner.loadOnce()
    }

    /// True while accurate recognition is failing on this host and requests use fast recognition.
    public static var usesFastFallback: Bool {
        levelPolicy.withLock { $0.level(at: .now) == .fast }
    }

    /// Returns recognized lines with boxes converted to a top left origin.
    ///
    /// With `regions`, in the frame's normalized top-left coordinates, only those parts are read,
    /// one Vision call each, which costs less than one call over the whole frame when the parts
    /// hold fewer lines. Boxes still come back in the whole frame's coordinates.
    public func recognizeText(
        in pixelBuffer: CVPixelBuffer, regions: [CGRect]? = nil
    ) async throws -> [RecognizedLine] {
        let level = Self.levelPolicy.withLock { $0.level(at: .now) }
        guard level == .accurate else {
            return try Self.recognize(pixelBuffer, level: .fast, regions: regions)
        }
        do {
            let lines = try Self.recognize(pixelBuffer, level: .accurate, regions: regions)
            Self.log(Self.levelPolicy.withLock { $0.accurateSucceeded() }, error: nil)
            return lines
        } catch {
            Self.log(Self.levelPolicy.withLock { $0.accurateFailed(at: .now) }, error: error)
            return try Self.recognize(pixelBuffer, level: .fast, regions: regions)
        }
    }

    /// Reads the whole frame, or each region in its own call. The caller decides what a failure
    /// means.
    private static func recognize(
        _ pixelBuffer: CVPixelBuffer,
        level: VNRequestTextRecognitionLevel,
        regions: [CGRect]?
    ) throws -> [RecognizedLine] {
        guard let regions else { return try recognize(pixelBuffer, level: level, region: nil) }
        return try regions.flatMap { try recognize(pixelBuffer, level: level, region: $0) }
    }

    /// Runs one request over the frame or over one region of it.
    private static func recognize(
        _ pixelBuffer: CVPixelBuffer,
        level: VNRequestTextRecognitionLevel,
        region: CGRect?
    ) throws -> [RecognizedLine] {
        let area = region ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let pixelHeight = Float(CVPixelBufferGetHeight(pixelBuffer)) * Float(area.height)
        guard pixelHeight > 0, area.width > 0 else { return [] }
        // Vision builds autoreleased images and Observers for every request. The queue that
        // calls this is a long running async task with no run loop, so without this pool the
        // frame's Vision memory would stay resident until an unrelated drain.
        return try autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "es-ES"]
            request.automaticallyDetectsLanguage = false
            // Preserve small UI glyphs at every capture height, including 1440p. The height is
            // a share of the region Vision reads.
            request.minimumTextHeight = minimumTextHeightPixels / pixelHeight
            if region != nil {
                request.regionOfInterest = CGRect(
                    x: area.minX, y: 1 - area.maxY, width: area.width, height: area.height)
            }
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first,
                    candidate.confidence >= minimumConfidence
                else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                // Vision answers in the region's coordinates; place the box in the frame.
                let box = Self.topLeftBox(fromVision: observation.boundingBox)
                return RecognizedLine(
                    text: text,
                    box: CGRect(
                        x: area.minX + box.minX * area.width, y: area.minY + box.minY * area.height,
                        width: box.width * area.width, height: box.height * area.height)
                )
            }
        }
    }

    /// Logs a level switch once per event, so a broken host does not fill the log.
    private static func log(_ transition: RecognitionLevelPolicy.Transition, error: Error?) {
        let seconds = RecognitionLevelPolicy.accurateRetryInterval.components.seconds
        switch transition {
        case .fellBack:
            let reason = error?.localizedDescription ?? "unknown error"
            let message =
                "Accurate text recognition failed (\(reason)); "
                + "using fast recognition for \(seconds) s"
            textRecognizerLog.notice("\(message, privacy: .public)")
        case .stayedFast:
            let message = "Accurate text recognition still fails; trying again in \(seconds) s"
            textRecognizerLog.debug("\(message, privacy: .public)")
        case .recovered:
            textRecognizerLog.notice("Accurate text recognition works again")
        case .unchanged:
            break
        }
    }

    /// Starts the load on the first call. Later calls await the task that the first call started.
    private func loadOnce() async -> Double {
        let task = warmUpTask ?? Task(priority: .utility) { await self.loadModels() }
        warmUpTask = task
        return await task.value
    }

    /// Recognizes a generated image, so the compile lands on no real frame.
    private func loadModels() async -> Double {
        let start = ContinuousClock.now
        if let image = TextWarmUpImage.make() {
            do {
                let lines = try await recognizeText(in: image)
                textRecognizerLog.notice("Warm-up request recognized \(lines.count) lines")
            } catch {
                textRecognizerLog.error(
                    "Warm-up recognition failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        } else {
            textRecognizerLog.error("Cannot create the OCR warm-up image")
        }
        return start.duration(to: ContinuousClock.now) / .milliseconds(1)
    }

    /// Converts Vision's bottom-left coordinates once, before boxes enter the recorder pipeline.
    private static func topLeftBox(fromVision box: CGRect) -> CGRect {
        let x = min(max(box.minX, 0), 1)
        let y = min(max(1 - box.maxY, 0), 1)
        let width = min(max(box.width, 0), 1 - x)
        let height = min(max(box.height, 0), 1 - y)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
