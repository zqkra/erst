import ErstModel
import Foundation
import Synchronization

/// Each screen receives its own stream, including the most recent status.
final class RecorderStatusBroadcast: Sendable {
    private struct State {
        var latest: RecorderStatus = .stopped
        var continuations: [UUID: AsyncStream<RecorderStatus>.Continuation] = [:]
    }
    private let state = Mutex(State())

    func stream() -> AsyncStream<RecorderStatus> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            state.withLock {
                $0.continuations[id] = continuation
                continuation.yield($0.latest)
            }
            continuation.onTermination = { [weak self] _ in
                _ = self?.state.withLock { $0.continuations.removeValue(forKey: id) }
            }
        }
    }

    func publish(_ status: RecorderStatus) {
        state.withLock {
            $0.latest = status
            for continuation in $0.continuations.values { continuation.yield(status) }
        }
    }
}
