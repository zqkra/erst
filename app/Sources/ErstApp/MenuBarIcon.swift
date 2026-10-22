import AppKit
import ErstModel
import ErstUI
import SwiftUI
import os

private let iconLog = Logger(subsystem: "app.erst.Erst", category: "MenuBarIcon")

struct MenuBarIcon: View {
    private static let sizePoints: CGFloat = 18
    private static let image: NSImage = {
        let size = NSSize(width: sizePoints, height: sizePoints)
        let scale: CGFloat = 2
        guard
            let context = CGContext(
                data: nil, width: Int(sizePoints * scale), height: Int(sizePoints * scale),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return NSImage(size: size) }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: sizePoints)
        context.scaleBy(x: 1, y: -1)
        context.addPath(ErstMark().path(in: CGRect(origin: .zero, size: size)).cgPath)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fillPath()
        guard let bitmap = context.makeImage() else { return NSImage(size: size) }
        let image = NSImage(cgImage: bitmap, size: size)
        image.isTemplate = true
        iconLog.notice("Menu bar item created with Erst template mark")
        return image
    }()

    let status: RecorderStatus
    /// Receives SwiftUI's settings action. The icon is on screen from launch, so a notification
    /// can open Settings before the menu was ever opened.
    let onSettingsAction: (OpenSettingsAction) -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(nsImage: Self.image)
            .opacity(isDimmed ? 0.5 : 1)
            .accessibilityLabel("Erst")
            .task { onSettingsAction(openSettings) }
    }

    private var isDimmed: Bool {
        switch status {
        case .paused, .needsPermission: true
        case .recording, .stopped: false
        }
    }
}
