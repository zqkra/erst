import CoreGraphics
import Foundation

/// The only seam between the screens and the recording engine.
public protocol MemoryService: Sendable {
    func timeline(in range: ClosedRange<Date>, buckets: Int) async throws -> TimelineSlice
    /// Every kept frame and app or site segment in the range, indexed for the timeline track.
    func timelineTrack(in range: ClosedRange<Date>) async throws -> TimelineTrack
    /// Heat for every wall-clock hour of the local days in the range, one `DayHeat` per day.
    func hourlyHeat(in range: ClosedRange<Date>) async throws -> [DayHeat]
    func moment(id: Moment.ID) async throws -> MomentDetail
    func nearestMoment(to date: Date) async throws -> Moment?
    func search(_ query: SearchQuery, limit: Int) async throws -> [SearchHit]
    /// Removes everything recorded in the range. Video segments that overlap it are deleted whole.
    func erase(_ range: ClosedRange<Date>) async throws
    func activity(in range: ClosedRange<Date>) async throws -> ActivityReport
    func todaySummary() async throws -> TodaySummary
    func storage() async throws -> StorageReport
    func image(for moment: Moment.ID, maxPixelSize: Int) async throws -> CGImage
    func settings() async throws -> ErstSettings
    func update(_ settings: ErstSettings) async throws
    func addReminder(for moment: Moment.ID?, at date: Date, note: String) async throws
    var status: AsyncStream<RecorderStatus> { get }
    var dataDirectory: URL { get }
    func setRecording(_ isRecording: Bool) async
}
