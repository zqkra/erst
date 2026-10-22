import Foundation

/// One completed OCR attempt, observed only within an explicitly instrumented task tree.
public struct OCRMeasurement: Sendable {
    /// Receives measurements from OCR jobs started within this task-local scope.
    @TaskLocal public static var observer: (@Sendable (OCRMeasurement) -> Void)?

    /// Capture time identifying the kept frame.
    public let capturedAt: Date
    /// Recognized line count, zero when recognition failed.
    public let lineCount: Int
    /// Recognition time, excluding the wait for a pending slot and persistence.
    public let milliseconds: Double
}
