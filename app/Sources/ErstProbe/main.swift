import Darwin
import ErstCore
import ErstKit
import Foundation

// Keep progress visible when the probe is redirected to a log file.
setvbuf(stdout, nil, _IOLBF, 0)

private func printPermissionHelp() {
    print(
        """
        Screen Recording permission is missing.
        Open System Settings, Privacy & Security, Screen & System Audio Recording,
        enable the terminal that runs this probe, then run it again.
        Command:
          open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        Accessibility is optional. Without it window titles and URLs stay empty.
        """
    )
}

private func makeDataDirectory(_ options: ProbeOptions) -> URL {
    if let provided = options.dataDirectory {
        return provided
    }
    return FileManager.default.temporaryDirectory
        .appendingPathComponent("ErstProbe-\(UUID().uuidString)", isDirectory: true)
}

let options: ProbeOptions
do {
    options = try ProbeOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    print("\(error)")
    print(ProbeOptions.usage)
    exit(1)
}

if options.isVerification {
    try await ProbeVerification.run()
    try await ProbeTextVerification.run()
    try await ProbeIncrementalVerification.run()
    try await ProbeAgentSkillVerification.run()
    try ProbeMergeVerification.run()
    try await ProbeSegmentGrowthVerification.run()
    try await ProbeLiveImageVerification.run()
    exit(0)
}

guard Permissions.screenRecordingGranted() else {
    printPermissionHelp()
    exit(2)
}

let dataDirectory = makeDataDirectory(options)
let engine: Engine
do {
    try FileManager.default.createDirectory(
        at: dataDirectory,
        withIntermediateDirectories: true
    )
    engine = try await Task.detached { try Engine.open(dataDir: dataDirectory.path) }.value
} catch {
    print("Cannot create \(dataDirectory.path): \(error.localizedDescription)")
    exit(1)
}

let adapter = EngineAdapter(engine: engine)
let timings = ProbeStageTimings()
let trace: ProbeKeepTrace?
do {
    trace = try options.traceURL.map { try ProbeKeepTrace.create(at: $0) }
} catch {
    print("Cannot create the keep trace: \(error.localizedDescription)")
    exit(1)
}
if let traceURL = options.traceURL {
    print("keep trace: \(traceURL.path)")
}
let configuration =
    options.isProduction
    ? ProbeProductionConfiguration.make()
    : RecorderConfiguration(
        captureInterval: 1,
        segmentDuration: 5,
        compression: .faster,
        idleThreshold: 86_400
    )
let mode = options.isProduction ? "production" : "short"
print("ErstProbe: \(mode) mode, recording for \(options.seconds)s into \(dataDirectory.path)")
print(
    "configuration: capture every \(configuration.captureInterval)s, "
        + "\(configuration.segmentDuration)s segments, \(configuration.compression.rawValue) compression, "
        + "idle after \(configuration.idleThreshold)s, "
        + "\(configuration.excludedBundleIDs.count) excluded apps"
)

let recorder = Recorder(
    dataDirectory: dataDirectory,
    keepEvaluator: ProbeTimedKeepEvaluator(adapter: adapter, timings: timings, trace: trace),
    memoryWriter: ProbeTimedMemoryWriter(adapter: adapter, timings: timings),
    configuration: configuration
)

var stateTask: Task<Void, Never>?
if !options.isProduction {
    stateTask = Task {
        for await state in recorder.states {
            print("[state] \(state.status) seen=\(state.framesSeen) kept=\(state.framesKept)")
        }
    }
}

let ocrMeasurements = ProbeOCRMeasurements(printsJobs: !options.isProduction)
let recorderStartedUptime = ProcessInfo.processInfo.systemUptime
await OCRMeasurement.$observer.withValue({ ocrMeasurements.record($0) }) {
    await recorder.start()
}
let startedState = await recorder.currentState()
guard startedState.status != .needsPermission else {
    stateTask?.cancel()
    printPermissionHelp()
    exit(2)
}

if options.isProduction {
    if options.disablesIdleGate {
        await recorder.apply(ProbeProductionConfiguration.disablingIdleGate(configuration))
        print("idle gate: disabled by --no-idle-gate")
    }
    let sampler = ProbeSampler(recorder: recorder, printsProgress: true)
    let samplingTask = Task { await sampler.run(for: .seconds(options.seconds)) }
    try? await Task.sleep(for: .seconds(options.seconds))
    await recorder.stop()
    samplingTask.cancel()
    await sampler.finish()
    let history = await sampler.history()
    try await ProbeProductionSummary.printSummary(
        engine: engine,
        recorder: recorder,
        dataDirectory: dataDirectory,
        configuration: configuration,
        history: history,
        timings: timings,
        idleGateDisabled: options.disablesIdleGate,
        recorderStartedUptime: recorderStartedUptime
    )
    if let trace {
        print(trace.finish())
    }
    exit(0)
}

if options.isControlExercise {
    try await Task.sleep(for: .seconds(Double(options.seconds) / 2))
    try await ProbeControls.exercise(recorder, engine: engine, configuration: configuration)
    try await Task.sleep(for: .seconds(Double(options.seconds) / 2))
} else {
    try? await Task.sleep(for: .seconds(options.seconds))
}
await recorder.stop()
await stateTask?.value

let metrics = await recorder.metrics()
let (summary, timeline) = try await Task.detached {
    // FfiStorage exposes frame and line counts, but no span count. Read persisted spans through timeline.
    try (
        engine.storage(),
        engine.timeline(startMs: 0, endMs: Int64(Date().timeIntervalSince1970 * 1000) + 1, buckets: 1)
    )
}.value
let bytesPerKept =
    metrics.framesKept > 0
    ? Double(summary.videoBytes) / Double(metrics.framesKept)
    : 0

print("")
print("ErstProbe summary")
print("frames seen: \(metrics.framesSeen)")
print("frames kept: \(metrics.framesKept)")
print("stored frames: \(summary.frameCount)")
print("stored unique lines: \(summary.uniqueLineCount)")
print("segments: \(summary.segmentCount)")
print("total video bytes: \(summary.videoBytes)")
print("bytes per kept frame: \(String(format: "%.0f", bytesPerKept))")
print("OCR lines: \(metrics.ocrLines)")
print("average OCR time: \(String(format: "%.1f", metrics.averageOCRMilliseconds)) ms")
if let warmUp = metrics.ocrWarmUpMilliseconds {
    print("OCR warm-up: \(String(format: "%.0f", warmUp)) ms")
} else {
    print("OCR warm-up: did not finish")
}
ocrMeasurements.printSummary()
print("average thumbnail time: \(String(format: "%.2f", metrics.averageThumbnailMilliseconds)) ms")
print("stored spans: \(timeline.spans.count)")
let framesWithoutText = try await Task.detached {
    let stamps = timeline.stamps.sorted { $0.capturedAtMs < $1.capturedAtMs }
    var missing = 0
    for stamp in stamps {
        let moment = try engine.moment(frameId: stamp.id, timeZone: "UTC")
        print("kept frame \(stamp.id): OCR lines=\(moment.lines.count)")
        if moment.lines.isEmpty { missing += 1 }
        if stamp.id == stamps.last?.id {
            print("latest frame, first three recognized lines:")
            for line in moment.lines.prefix(3) {
                print("  \(line.text)")
            }
        }
    }
    return missing
}.value
print("kept frames with OCR text: \(timeline.stamps.count - framesWithoutText) of \(timeline.stamps.count)")
if let latest = await recorder.latestFrame() {
    print("latest cached frame: \(latest.id), \(latest.image.width)x\(latest.image.height)")
}
if framesWithoutText > 0 {
    print("OCR coverage check failed: \(framesWithoutText) kept frames have no text")
    exit(1)
}
if let trace {
    print(trace.finish())
}
print("OCR coverage check passed: every kept frame has text")
