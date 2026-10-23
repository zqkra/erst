import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import os

private let segmentWriterLog = Logger(subsystem: "app.erst.Erst", category: "SegmentWriter")
private let sourceFrameRate = 1

/// Writes kept frames into short fragmented HEVC segments.
public actor SegmentWriter {
    private let dataDirectory: URL
    private var compression: Compression
    private var segmentDuration: TimeInterval
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    private var writer: AVAssetWriter?
    private var receiver: AVAssetWriterInput.PixelBufferReceiver?
    private var current: SegmentHandle?
    private var lastPresentationMilliseconds: Int64 = -1
    private var lastFrameAt: Date?

    /// Creates a writer that stores segments below the given data directory.
    public init(
        dataDirectory: URL,
        compression: Compression = .faster,
        segmentDuration: TimeInterval = 300
    ) {
        self.dataDirectory = dataDirectory
        self.compression = compression
        self.segmentDuration = max(1, segmentDuration)
    }

    /// Appends one kept frame, rotating the segment on a size change or on the duration limit.
    public func append(_ frame: CapturedFrame) async throws -> AppendResult {
        await acquireOperation()
        defer { releaseOperation() }
        let width = CVPixelBufferGetWidth(frame.pixelBuffer)
        let height = CVPixelBufferGetHeight(frame.pixelBuffer)
        guard width > 1, height > 1 else {
            throw SegmentWriterError.invalidFrameSize
        }

        var rotated: FinishedSegment?
        if writer != nil, shouldRotate(width: width, height: height, at: frame.capturedAt) {
            rotated = await closeCurrent(endedAt: currentEndDate)
        }
        if writer == nil {
            try startSegment(width: width, height: height, at: frame.capturedAt)
        }

        var pts = presentationTime(for: frame.capturedAt)
        do {
            try appendBuffer(frame.pixelBuffer, capturedAt: frame.capturedAt, presentationMilliseconds: pts)
        } catch {
            let message =
                "Encoder rejected a frame, starting a new segment: "
                + "\(error.localizedDescription)"
            segmentWriterLog.error("\(message, privacy: .public)")
            if let failed = await closeCurrent(endedAt: currentEndDate) {
                if rotated == nil {
                    rotated = failed
                } else {
                    segmentWriterLog.error(
                        "Two segments finished in one append, reporting \(failed.handle.relativePath, privacy: .public)"
                    )
                }
            }
            try startSegment(width: width, height: height, at: frame.capturedAt)
            pts = presentationTime(for: frame.capturedAt)
            try appendBuffer(frame.pixelBuffer, capturedAt: frame.capturedAt, presentationMilliseconds: pts)
        }

        guard let current else { throw SegmentWriterError.notStarted }
        return AppendResult(segment: current, ptsMilliseconds: pts, rotatedFrom: rotated)
    }

    /// Closing a segment flushes a few seconds of frames. One that takes longer is stuck inside
    /// the system, and recording must not wait for it.
    private static let finishDeadline = Duration.seconds(20)

    /// Closes the open segment and returns it with its final file size.
    public func finish() async throws -> FinishedSegment? {
        await acquireOperation()
        defer { releaseOperation() }
        guard let current else { return nil }
        return await closeCurrent(endedAt: lastFrameAt ?? current.startedAt)
    }

    func apply(compression: Compression, segmentDuration: TimeInterval) {
        self.compression = compression
        self.segmentDuration = max(1, segmentDuration)
    }

    private func acquireOperation() async {
        if !operationInProgress {
            operationInProgress = true
            return
        }
        await withCheckedContinuation { operationWaiters.append($0) }
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            operationInProgress = false
        } else {
            operationWaiters.removeFirst().resume()
        }
    }

    private func startSegment(width: Int, height: Int, at date: Date) throws {
        let relativePath = Self.makeRelativePath(for: date)
        let fileURL = dataDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
        let settings = HEVCSettings.outputSettings(
            width: width,
            height: height,
            compression: compression
        )
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        do {
            try writer.start()
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw SegmentWriterError.startFailed(error.localizedDescription)
        }
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.receiver = receiver
        self.current = SegmentHandle(
            relativePath: relativePath,
            startedAt: date,
            width: width,
            height: height
        )
        self.lastPresentationMilliseconds = -1
        self.lastFrameAt = nil
    }

    private func appendBuffer(
        _ pixelBuffer: CVPixelBuffer,
        capturedAt: Date,
        presentationMilliseconds: Int64
    ) throws {
        try autoreleasepool {
            guard let writer, let receiver else { throw SegmentWriterError.notStarted }
            let box = PixelBufferBox(pixelBuffer)
            let appended = try receiver.appendImmediately(
                box.readOnly,
                with: CMTime(value: presentationMilliseconds, timescale: 1000)
            )
            guard appended, writer.status == .writing else {
                throw SegmentWriterError.appendFailed(
                    writer.error?.localizedDescription ?? "The writer is not accepting frames."
                )
            }
            lastFrameAt = capturedAt
        }
    }

    private func presentationTime(for date: Date) -> Int64 {
        guard let current else { return 0 }
        let raw = Int64((date.timeIntervalSince(current.startedAt) * 1000).rounded())
        let pts = max(0, max(raw, lastPresentationMilliseconds + 1))
        lastPresentationMilliseconds = pts
        return pts
    }

    private var currentEndDate: Date {
        lastFrameAt ?? current?.startedAt ?? Date()
    }

    private func shouldRotate(width: Int, height: Int, at date: Date) -> Bool {
        guard let current else { return true }
        if width != current.width || height != current.height {
            return true
        }
        return date.timeIntervalSince(current.startedAt) >= segmentDuration
    }

    private func closeCurrent(endedAt: Date) async -> FinishedSegment? {
        guard let writer, let current else { return nil }
        receiver?.finish()
        let finished = await Deadline.wait(within: Self.finishDeadline) { done in
            writer.finishWriting { done() }
        }
        if !finished {
            // The file keeps every fragment already written; recording goes on in a new segment.
            segmentWriterLog.error(
                "Finishing \(current.relativePath, privacy: .public) did not complete in time; moving on")
        } else if writer.status == .failed {
            let message =
                "Finishing \(current.relativePath) failed: "
                + "\(writer.error?.localizedDescription ?? "unknown")"
            segmentWriterLog.error("\(message, privacy: .public)")
        }
        let fileURL = dataDirectory.appendingPathComponent(current.relativePath)
        let bytes = fileSize(at: fileURL)
        self.writer = nil
        self.receiver = nil
        self.current = nil
        self.lastPresentationMilliseconds = -1
        self.lastFrameAt = nil
        guard bytes > 0 else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return FinishedSegment(handle: current, endedAt: endedAt, bytes: bytes)
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize
        else { return 0 }
        return Int64(size)
    }

    private static func makeRelativePath(for date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        let dayPath = String(format: "%04d/%02d/%02d", year, month, day)
        let stamp = String(format: "%02d%02d%02d", hour, minute, second)
        let suffix = String(
            UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        ).lowercased()
        return "segments/\(dayPath)/\(stamp)-\(suffix).mp4"
    }
}
