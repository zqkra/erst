import Foundation

/// An application identified the same way the capture pipeline identifies it.
public struct AppRef: Codable, Hashable, Identifiable, Sendable {
    public let bundleID: String
    public let name: String

    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}
