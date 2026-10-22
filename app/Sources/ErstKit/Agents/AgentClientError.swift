import Foundation

/// A configuration could not be read, backed up, or updated safely.
public enum AgentClientError: Error, LocalizedError, Sendable {
    case invalidConfiguration(file: URL, reason: String)
    case readFailed(file: URL, reason: String)
    case backupFailed(file: URL, reason: String)
    case writeFailed(file: URL, reason: String)
    case commandLineFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let file, let reason):
            "Invalid agent configuration at \(file.path): \(reason)"
        case .readFailed(let file, let reason):
            "Could not read \(file.path): \(reason)"
        case .backupFailed(let file, let reason):
            "Could not back up \(file.path): \(reason)"
        case .writeFailed(let file, let reason):
            "Could not update \(file.path): \(reason)"
        case .commandLineFailed(let reason):
            "Could not change the erst command: \(reason)"
        }
    }
}
