import ErstCore
import ErstModel
import Foundation

/// Serializes synchronous Engine reads and maintenance away from the main actor.
public actor LiveEngine {
    private let engine: Engine

    private init(engine: Engine) { self.engine = engine }

    public static func open(at directory: URL) async throws -> LiveEngine {
        try await Task.detached(priority: .userInitiated) {
            LiveEngine(engine: try Engine.open(dataDir: directory.path))
        }.value
    }

    func call<Value: Sendable>(_ body: @Sendable (Engine) throws -> Value) rethrows -> Value {
        try body(engine)
    }

    func recorder(at directory: URL, settings: ErstSettings) -> Recorder {
        let adapter = EngineAdapter(engine: engine)
        return Recorder(
            dataDirectory: directory, keepEvaluator: adapter, memoryWriter: adapter,
            configuration: FfiConversions.configuration(settings))
    }
}
