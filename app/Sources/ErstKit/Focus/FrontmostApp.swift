import Foundation

/// A frontmost application reduced to the values that can cross actor boundaries.
struct FrontmostApp: Sendable, Equatable {
    let processID: pid_t
    let bundleID: String
    let appName: String
}
