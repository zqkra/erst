import Foundation
import Synchronization

/// Waits for work that macOS may never finish, such as a Vision read or a video writer closing a
/// file. Past the deadline the caller moves on; the work keeps running on its own and its result
/// is dropped, because a call stuck inside the system cannot be cancelled from outside.
enum Deadline {
    /// The operation's result, or nil when the deadline passed first.
    static func run<T: Sendable>(
        within duration: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        let gate = Gate()
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task {
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled, gate.open() else { return }
                continuation.resume(returning: nil)
            }
            Task {
                do {
                    let value = try await operation()
                    timer.cancel()
                    if gate.open() { continuation.resume(returning: value) }
                } catch {
                    timer.cancel()
                    if gate.open() { continuation.resume(throwing: error) }
                }
            }
        }
    }

    /// Starts work that reports completion through a handler, on the caller's actor, and answers
    /// whether it finished before the deadline.
    static func wait(
        within duration: Duration,
        isolation: isolated (any Actor)? = #isolation,
        _ start: (_ done: @escaping @Sendable () -> Void) -> Void
    ) async -> Bool {
        let gate = Gate()
        return await withCheckedContinuation { continuation in
            let timer = Task {
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled, gate.open() else { return }
                continuation.resume(returning: false)
            }
            start {
                timer.cancel()
                if gate.open() { continuation.resume(returning: true) }
            }
        }
    }
}

/// Lets exactly one of two racers resume a continuation.
private final class Gate: Sendable {
    private let opened = Mutex(false)

    func open() -> Bool {
        opened.withLock { opened in
            guard !opened else { return false }
            opened = true
            return true
        }
    }
}
