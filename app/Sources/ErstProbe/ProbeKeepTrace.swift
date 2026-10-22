import ErstKit
import Foundation
import Synchronization

/// Appends every captured thumbnail to a trace that `replay_keep` reads.
///
/// The file is one header and then one fixed-size record per captured frame,
/// all integers little endian:
///
/// ```text
/// header: "ERSTTRE1" (8 bytes), width (u32), height (u32)
/// record: captured_at_ms (i64), focus_changed (u8, 0 or 1), luma (width * height bytes)
/// ```
///
/// A run killed mid-write leaves one partial record at the end. The replay tool
/// ignores it. The header is written once when the trace is created, so an empty
/// trace is still a valid trace with no frames.
final class ProbeKeepTrace: Sendable {
    private static let magic: [UInt8] = Array("ERSTTRE1".utf8)
    private static let headerBytes = 16

    private let handle: FileHandle
    private let width: Int
    private let height: Int
    private let counters = Mutex<Counters>(Counters())

    private struct Counters {
        var frames = 0
        var bytes = UInt64(ProbeKeepTrace.headerBytes)
        var mismatched = 0
        var writeFailures = 0
    }

    private init(handle: FileHandle, width: Int, height: Int) {
        self.handle = handle
        self.width = width
        self.height = height
    }

    /// Creates or truncates the trace file and writes its header.
    ///
    /// The thumbnail size is fixed by `Thumbnailer`, so the header can describe
    /// every record before the first frame arrives.
    static func create(at url: URL) throws -> ProbeKeepTrace {
        let path = url.path
        FileManager.default.createFile(atPath: path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        var header = magic
        header.append(
            contentsOf: withUnsafeBytes(of: UInt32(Thumbnail.standardWidth).littleEndian) { Array($0) })
        header.append(
            contentsOf: withUnsafeBytes(of: UInt32(Thumbnail.standardHeight).littleEndian) { Array($0) })
        try handle.write(contentsOf: header)
        return ProbeKeepTrace(
            handle: handle, width: Thumbnail.standardWidth, height: Thumbnail.standardHeight)
    }

    /// Appends one captured thumbnail and whether its focus changed.
    func append(_ thumbnail: Thumbnail, at date: Date, focusChanged: Bool) {
        guard thumbnail.width == width, thumbnail.height == height else {
            counters.withLock { $0.mismatched += 1 }
            return
        }
        let milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
        var record = withUnsafeBytes(of: milliseconds.littleEndian) { Array($0) }
        record.append(focusChanged ? 1 : 0)
        record.append(contentsOf: thumbnail.luma)
        do {
            try handle.write(contentsOf: record)
        } catch {
            counters.withLock { $0.writeFailures += 1 }
            return
        }
        counters.withLock {
            $0.frames += 1
            $0.bytes += UInt64(record.count)
        }
    }

    /// Closes the file and reports what was written.
    func finish() -> String {
        try? handle.close()
        let counts = counters.withLock { $0 }
        var summary =
            "trace: \(counts.frames) frames, \(String(format: "%.1f", Double(counts.bytes) / 1_000_000)) MB"
        if counts.mismatched > 0 {
            summary += ", \(counts.mismatched) thumbnails of another size skipped"
        }
        if counts.writeFailures > 0 {
            summary += ", \(counts.writeFailures) writes failed"
        }
        return summary
    }
}
