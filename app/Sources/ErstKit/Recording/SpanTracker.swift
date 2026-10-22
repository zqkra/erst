import Foundation
import os

private let spanLog = Logger(subsystem: "app.erst.Erst", category: "SpanTracker")

/// Opens and closes activity spans through the memory writer.
struct SpanTracker: Sendable {
    private let memoryWriter: any MemoryWriter
    private var openSpanID: Int64?

    init(memoryWriter: any MemoryWriter) {
        self.memoryWriter = memoryWriter
    }

    mutating func begin(focus: FocusContext, at date: Date) {
        guard openSpanID == nil else { return }
        do {
            openSpanID = try memoryWriter.beginSpan(
                bundleID: focus.bundleID,
                appName: focus.appName,
                windowTitle: focus.windowTitle,
                url: focus.url,
                at: date
            )
        } catch {
            spanLog.error(
                "Starting a span failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    mutating func end(at date: Date) {
        guard let id = openSpanID else { return }
        openSpanID = nil
        do {
            try memoryWriter.endSpan(id: id, at: date)
        } catch {
            let message = "Ending span \(id) failed: \(error.localizedDescription)"
            spanLog.error("\(message, privacy: .public)")
        }
    }
}
