import Foundation

/// A newer version of Erst that the updater found in the release feed.
public struct SoftwareUpdateOffer: Equatable, Sendable {
    public let version: String
    /// What changed, one sentence per line.
    public let notes: [String]
    public let size: Int64?
    public let releasedAt: Date?

    public init(version: String, notes: [String], size: Int64?, releasedAt: Date?) {
        self.version = version
        self.notes = notes
        self.size = size
        self.releasedAt = releasedAt
    }
}

/// Where the update stands, as Settings and the menu bar show it.
public enum SoftwareUpdatePhase: Equatable, Sendable {
    /// Nothing newer. `lastChecked` is nil until the first check.
    case upToDate(lastChecked: Date?)
    case checking
    case available(SoftwareUpdateOffer)
    case downloading(SoftwareUpdateOffer, received: Int64, expected: Int64?)
    /// Checking the download's signature and unpacking it.
    case preparing(SoftwareUpdateOffer)
    /// Downloaded and verified; it installs when Erst relaunches.
    case ready(SoftwareUpdateOffer)
    case installing(SoftwareUpdateOffer)
    case failed(message: String, lastChecked: Date?)

    /// The update this phase is about, if any.
    public var offer: SoftwareUpdateOffer? {
        switch self {
        case .available(let offer), .preparing(let offer), .ready(let offer), .installing(let offer):
            offer
        case .downloading(let offer, _, _):
            offer
        case .upToDate, .checking, .failed:
            nil
        }
    }
}
