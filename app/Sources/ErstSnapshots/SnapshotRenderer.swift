import AppKit
import ErstUI
import SwiftUI

/// Renders a real hosted window at two pixels per point.
@MainActor
struct SnapshotRenderer {
    let folder: URL
    static let scale: CGFloat = 2
    private let initialHeight: CGFloat = 900
    private let minimumFittedHeight: CGFloat = 200
    private let layoutSettleSeconds: TimeInterval = 0.3
    private let contentSettleSeconds: TimeInterval = 1.4
    private let layoutTickMilliseconds = 25
    private let readinessTimeoutSeconds: TimeInterval = 10
    private let readinessPollMilliseconds = 50

    func captureOverlay<V: View>(
        _ view: V, name: String, panelSize: CGSize, isReady: (() -> Bool)? = nil
    ) async throws {
        try await capture(
            SnapshotStage(panelSize: panelSize) { view },
            name: name,
            width: SnapshotStageMetrics.stageWidthPoints,
            height: SnapshotStageMetrics.stageHeightPoints,
            isReady: isReady
        )
    }

    func capture<V: View>(
        _ view: V, name: String, width: CGFloat, height: CGFloat? = nil,
        isReady: (() -> Bool)? = nil
    ) async throws {
        let hosting = NSHostingView(
            rootView:
                view
                .environment(\.colorScheme, .dark)
                .environment(\.erstOpaquePanels, true)
                .font(Typography.body.font)
                .tint(Color.erstButter)
                .background(Color.erstGround)
        )
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: height ?? initialHeight)
        let window = SnapshotWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Color.erstGround)
        window.isOpaque = true
        window.contentView = hosting
        window.setFrameOrigin(.zero)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        defer { window.orderOut(nil) }
        try await settle(hosting, seconds: layoutSettleSeconds)

        let resolvedHeight = height ?? max(minimumFittedHeight, hosting.fittingSize.height)
        hosting.frame.size = NSSize(width: width, height: resolvedHeight)
        window.setContentSize(hosting.frame.size)
        window.setFrameOrigin(.zero)
        if let isReady {
            try await settle(hosting, until: isReady, name: name)
        }
        try await settle(hosting, seconds: contentSettleSeconds)

        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(width * Self.scale), pixelsHigh: Int(resolvedHeight * Self.scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )
        else { throw SnapshotError.bitmap }
        bitmap.size = hosting.frame.size
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.png
        }
        let url = folder.appending(path: "\(name).png")
        try data.write(to: url)
        print("\(url.lastPathComponent): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
    }

    private func settle(_ view: NSView, seconds: TimeInterval) async throws {
        let steps = Int(seconds * 1000 / Double(layoutTickMilliseconds))
        for _ in 0..<steps {
            try await Task.sleep(for: .milliseconds(layoutTickMilliseconds))
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
        }
    }

    /// Waits for a screen to finish loading instead of guessing a longer fixed pause.
    private func settle(_ view: NSView, until isReady: () -> Bool, name: String) async throws {
        let deadline = Date().addingTimeInterval(readinessTimeoutSeconds)
        while !isReady() {
            guard Date() < deadline else {
                print("\(name).png: content not ready after \(Int(readinessTimeoutSeconds))s")
                return
            }
            try await Task.sleep(for: .milliseconds(readinessPollMilliseconds))
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
        }
    }
}

private final class SnapshotWindow: NSWindow {
    // A connected 1x display must not lower the resolution of offscreen SwiftUI layers.
    override var backingScaleFactor: CGFloat { SnapshotRenderer.scale }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
