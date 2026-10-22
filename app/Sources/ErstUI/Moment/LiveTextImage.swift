import AppKit
import SwiftUI
import VisionKit

/// A frame with VisionKit Live Text on top, so every word is selectable.
public struct LiveTextImage: NSViewRepresentable {
    private let image: CGImage

    public init(image: CGImage) {
        self.image = image
    }

    public func makeNSView(context: Context) -> LiveTextContainer {
        let view = LiveTextContainer()
        view.setImage(image)
        return view
    }

    public func updateNSView(_ nsView: LiveTextContainer, context: Context) {
        nsView.setImage(image)
    }
}

/// Keeps the image and its analysis overlay in sync.
public final class LiveTextContainer: NSView {
    private let imageView = NSImageView()
    private let overlay = ImageAnalysisOverlayView()
    private let analyzer = ImageAnalyzer()
    private var imageIdentifier: ObjectIdentifier?
    private var analysisTask: Task<Void, Never>?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.autoresizingMask = [.width, .height]
        overlay.autoresizingMask = [.width, .height]
        overlay.preferredInteractionTypes = .automaticTextOnly
        overlay.trackingImageView = imageView
        addSubview(imageView)
        addSubview(overlay)
    }

    required init?(coder: NSCoder) {
        nil
    }

    public override func layout() {
        super.layout()
        imageView.frame = bounds
        overlay.frame = bounds
    }

    func setImage(_ image: CGImage) {
        let identifier = ObjectIdentifier(image)
        guard identifier != imageIdentifier else { return }
        analysisTask?.cancel()
        imageIdentifier = identifier
        imageView.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        overlay.analysis = nil
        let analyzer = analyzer
        analysisTask = Task { [weak self] in
            let configuration = ImageAnalyzer.Configuration([.text])
            guard
                let analysis = try? await analyzer.analyze(
                    image,
                    orientation: .up,
                    configuration: configuration
                )
            else { return }
            guard !Task.isCancelled, self?.imageIdentifier == identifier else { return }
            self?.overlay.analysis = analysis
        }
    }
}
