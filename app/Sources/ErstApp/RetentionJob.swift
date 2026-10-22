import ErstKit
import Foundation
import os

private let retentionJobLog = Logger(subsystem: "app.erst.Erst", category: "RetentionJob")

@MainActor
final class RetentionJob {
    private static let launchDelaySeconds = 120
    private static let intervalSeconds = 3600
    private let task: Task<Void, Never>

    init(service: LiveMemoryService) {
        task = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(for: .seconds(Self.launchDelaySeconds))
                while !Task.isCancelled {
                    do { try await service.runRetention() } catch is CancellationError { return } catch {
                        retentionJobLog.error(
                            "Retention failed: \(error.localizedDescription, privacy: .public)")
                    }
                    try await Task.sleep(for: .seconds(Self.intervalSeconds))
                }
            } catch is CancellationError {
                return
            } catch {
                retentionJobLog.error(
                    "Retention loop stopped: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop() async {
        task.cancel()
        await task.value
    }
}
