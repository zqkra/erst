import AppKit
import CoreGraphics
import CoreMedia
import Darwin
import Foundation
import ScreenCaptureKit
import os

private let captureLog = Logger(subsystem: "app.erst.Erst", category: "CaptureService")
private let maximumOutputWidth = 2560
private let restartLimitSeconds = 30.0

/// Runs a ScreenCaptureKit display stream and delivers complete BGRA frames.
public actor CaptureService {
    /// Complete frames, newest first when the consumer falls behind.
    public nonisolated let frames: AsyncStream<CapturedFrame>

    private var configuration: CaptureServiceConfiguration
    private let continuation: AsyncStream<CapturedFrame>.Continuation
    private let sampleQueue = DispatchQueue(
        label: "app.erst.Erst.capture",
        qos: .userInitiated
    )

    private var stream: SCStream?
    private var streamID: UUID?
    private var output: CaptureOutput?
    private var displayID: CGDirectDisplayID?
    private var excludedBundleIDs: Set<String>
    private var stopping = false
    private var sleeping = false
    private var observersInstalled = false
    private var restarting = false
    private var restartAttempts = 0
    private var restartTask: Task<Void, Never>?

    private var displayTask: Task<Void, Never>?
    private var preferredDisplayID: CGDirectDisplayID?
    private var updating = false
    private var updateWaiters: [CheckedContinuation<Void, Never>] = []
    private var desiredRevision: UInt64 = 0
    private var appliedRevision: UInt64 = 0
    private var captureGeneration: UInt64 = 0
    private var defaultTokens: [NSObjectProtocol] = []

    /// Creates a capture service. Call `start()` to open the stream.
    public init(configuration: CaptureServiceConfiguration = CaptureServiceConfiguration()) {
        self.configuration = configuration
        self.excludedBundleIDs = configuration.excludedBundleIDs
        let (stream, continuation) = AsyncStream.makeStream(
            of: CapturedFrame.self,
            bufferingPolicy: .bufferingNewest(2)
        )
        self.frames = stream
        self.continuation = continuation
    }

    /// Opens the stream for the focused display, falling back to the pointer and main display.
    public func start() async throws {
        guard !stopping else { throw CaptureError.stopped }
        installObservers()
        try await startStream()
    }

    /// Stops the stream, removes observers, and finishes the frame stream.
    public func stop() async {
        guard !stopping else { return }
        stopping = true
        restartTask?.cancel()
        restartTask = nil
        removeObservers()
        displayTask?.cancel()
        displayTask = nil
        await stopStream()
        continuation.finish()
    }

    /// Replaces the excluded apps and updates the running content filter.
    public func updateContentFilter(excluding bundleIDs: Set<String>) async {
        excludedBundleIDs = bundleIDs
        configuration.excludedBundleIDs = bundleIDs
        desiredRevision &+= 1
        await refreshStream()
    }

    func apply(_ configuration: CaptureServiceConfiguration) async {
        self.configuration = configuration
        excludedBundleIDs = configuration.excludedBundleIDs
        desiredRevision &+= 1
        await refreshStream()
    }

    func setSystemActive(_ active: Bool) async {
        let shouldSleep = !active
        guard sleeping != shouldSleep else { return }
        if active {
            handleDidWake()
        } else {
            await handleWillSleep()
        }
    }

    private func followActiveDisplay() async {
        guard !stopping, !sleeping else { return }
        // Locating the focused window costs an Accessibility query or a full window list
        // scan. With one display there is nothing to follow, so skip it on every tick.
        guard CaptureDisplay.hasMultiple() else { return }
        if let activeID = await ActiveDisplay.currentID(), activeID != preferredDisplayID {
            preferredDisplayID = activeID
            desiredRevision &+= 1
        }
        if desiredRevision != appliedRevision { await refreshStream() }
    }

    private func refreshStream() async {
        if updating {
            await withCheckedContinuation { updateWaiters.append($0) }
            if stream != nil, !stopping, !sleeping, appliedRevision != desiredRevision {
                await refreshStream()
            }
            return
        }
        updating = true
        defer {
            updating = false
            let waiters = updateWaiters
            updateWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        repeat {
            let revision = desiredRevision
            guard let stream, !stopping, !sleeping else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                guard self.stream === stream, !stopping, !sleeping,
                    let display = display(in: content, matching: preferredDisplayID ?? displayID)
                else { return }
                output?.setSource(nil)
                try await stream.updateContentFilter(
                    makeFilter(display: display, applications: content.applications))
                try await stream.updateConfiguration(makeStreamConfiguration(for: display.displayID))
                guard self.stream === stream, !stopping, !sleeping else { return }
                captureGeneration &+= 1
                displayID = display.displayID
                appliedRevision = revision
                output?.setSource((display.displayID, captureGeneration))
            } catch {
                captureLog.error("Updating capture failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            if revision == desiredRevision { return }
        } while !stopping
    }

    private func startStream() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard !stopping else { throw CaptureError.stopped }
        guard !sleeping else { return }
        let activeDisplayID = await ActiveDisplay.currentID()
        preferredDisplayID = activeDisplayID ?? preferredDisplayID
        let targetDisplayID = preferredDisplayID ?? CaptureDisplay.underPointer()
        guard let display = display(in: content, matching: targetDisplayID) else {
            throw CaptureError.noDisplay
        }
        let filter = makeFilter(display: display, applications: content.applications)
        let streamConfiguration = makeStreamConfiguration(for: display.displayID)
        let revision = desiredRevision
        captureGeneration &+= 1
        let streamID = UUID()
        let output = CaptureOutput(
            displayID: display.displayID,
            generation: captureGeneration,
            onFrame: { [weak self] frame, generation in
                guard let self else { return }
                Task { await self.deliver(frame, generation: generation) }
            },
            onStop: { [weak self] error in
                guard let self else { return }
                Task { await self.handleStreamStopped(error, streamID: streamID) }
            }
        )
        let stream = SCStream(
            filter: filter,
            configuration: streamConfiguration,
            delegate: output
        )
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        guard !stopping else {
            try? await stream.stopCapture()
            throw CaptureError.stopped
        }
        guard !sleeping else {
            try? await stream.stopCapture()
            return
        }
        self.stream = stream
        self.streamID = streamID
        self.output = output
        self.displayID = display.displayID
        appliedRevision = revision
        restartAttempts = 0
        startDisplayFollowing()
        if revision != desiredRevision { await refreshStream() }
        let size = "\(streamConfiguration.width)x\(streamConfiguration.height)"
        captureLog.notice(
            "Capture started on display \(display.displayID, privacy: .public) at \(size, privacy: .public)"
        )
    }

    private func stopStream() async {
        let stream = self.stream
        let output = self.output
        self.stream = nil
        self.streamID = nil
        self.output = nil
        output?.setSource(nil)
        if let stream, let output {
            try? stream.removeStreamOutput(output, type: .screen)
        }
        if let stream {
            try? await stream.stopCapture()
        }
    }

    private func deliver(_ frame: CapturedFrame, generation: UInt64) {
        guard !stopping, !sleeping, !updating, generation == captureGeneration else { return }
        continuation.yield(frame)
    }

    private func handleStreamStopped(_ error: any Error, streamID: UUID) async {
        guard self.streamID == streamID, !stopping, !sleeping, !restarting else { return }
        captureLog.error(
            "Screen capture stopped: \(error.localizedDescription, privacy: .public)"
        )
        await stopStream()
        scheduleRestart(resetBackoff: false)
    }

    private func handleWillSleep() async {
        guard !stopping else { return }
        sleeping = true
        restartTask?.cancel()
        restartTask = nil
        await stopStream()
        captureLog.notice("Capture paused for sleep or lock")
    }

    private func handleDidWake() {
        guard !stopping else { return }
        sleeping = false
        scheduleRestart(resetBackoff: true)
        captureLog.notice("Capture resuming after wake")
    }

    private func scheduleRestart(resetBackoff: Bool) {
        guard !stopping, !sleeping, restartTask == nil else { return }
        if resetBackoff {
            restartAttempts = 0
        }
        restartAttempts += 1
        let delay = min(
            restartLimitSeconds,
            pow(2.0, Double(max(0, restartAttempts - 1)))
        )
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.runRestart()
        }
    }

    private func runRestart() async {
        restartTask = nil
        guard !stopping, !sleeping else { return }
        restarting = true
        await stopStream()
        defer { restarting = false }
        do {
            try await startStream()
        } catch {
            captureLog.error(
                "Capture restart failed: \(error.localizedDescription, privacy: .public)"
            )
            scheduleRestart(resetBackoff: false)
        }
    }

    private func makeFilter(
        display: SCDisplay,
        applications: [SCRunningApplication]
    ) -> SCContentFilter {
        let ownProcess = getpid()
        let excluded = applications.filter { application in
            application.processID == ownProcess
                || excludedBundleIDs.contains(application.bundleIdentifier)
        }
        return SCContentFilter(
            display: display,
            excludingApplications: excluded,
            exceptingWindows: []
        )
    }

    private func makeStreamConfiguration(for displayID: CGDirectDisplayID) -> SCStreamConfiguration {
        let pixelWidth = max(1, Int(CGDisplayPixelsWide(displayID)))
        let pixelHeight = max(1, Int(CGDisplayPixelsHigh(displayID)))
        let width = min(pixelWidth, maximumOutputWidth)
        var height = Int(
            (Double(pixelHeight) * Double(width) / Double(pixelWidth)).rounded()
        )
        height = max(2, height & ~1)

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.scalesToFit = true
        configuration.captureResolution = .best
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(
            seconds: self.configuration.captureInterval,
            preferredTimescale: 600
        )
        return configuration
    }

    private func display(
        in content: SCShareableContent,
        matching preferredID: CGDirectDisplayID?
    ) -> SCDisplay? {
        if let preferredID, let match = content.displays.first(where: { $0.displayID == preferredID }) {
            return match
        }
        return content.displays.first
    }

    private func startDisplayFollowing() {
        guard displayTask == nil else { return }
        displayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await self?.followActiveDisplay()
            }
        }
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let center = NotificationCenter.default
        let displayToken = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleDisplayChange() }
        }
        defaultTokens.append(displayToken)
    }

    private func handleDisplayChange() async {
        guard !stopping, !sleeping else { return }
        preferredDisplayID = await ActiveDisplay.currentID() ?? preferredDisplayID
        desiredRevision &+= 1
        await refreshStream()
    }

    private func removeObservers() {
        for token in defaultTokens {
            NotificationCenter.default.removeObserver(token)
        }
        defaultTokens.removeAll()
    }
}
