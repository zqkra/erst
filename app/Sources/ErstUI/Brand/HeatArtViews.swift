import Combine
import SwiftUI

/// The welcome's heat art. It plays once when it appears and then rests on its last frame; with
/// Reduce Motion it shows the rest at once.
public struct WelcomeEcho: View {
    @StateObject private var model = WelcomeEchoModel()
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        TimelineView(.animation(paused: model.isResting)) { context in
            if let image = model.image(at: context.date, scale: displayScale) {
                Image(decorative: image, scale: displayScale)
            }
        }
        .frame(width: WelcomeArt.size.width, height: WelcomeArt.size.height)
        .onAppear { model.play(reduceMotion: reduceMotion) }
        .accessibilityHidden(true)
    }
}

@MainActor
private final class WelcomeEchoModel: ObservableObject {
    @Published private(set) var isResting = false
    private var start: Date?
    private var restingSeconds = WelcomeArt.duration
    private var restingImage: CGImage?

    func play(reduceMotion: Bool) {
        // Snapshots hold arrivals part of the way in; the echo holds at the same share of its run.
        if let held = Motion.heldArrival {
            restingSeconds = WelcomeArt.duration * Double(held)
            isResting = true
            return
        }
        guard !reduceMotion else {
            isResting = true
            return
        }
        guard start == nil else { return }
        start = Date()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(WelcomeArt.duration))
            self?.isResting = true
        }
    }

    func image(at date: Date, scale: CGFloat) -> CGImage? {
        if isResting, let restingImage { return restingImage }
        let seconds = isResting ? restingSeconds : start.map { date.timeIntervalSince($0) } ?? 0
        let image = HeatCanvas.render(
            WelcomeArt.strokes(at: seconds), size: WelcomeArt.size, scale: scale,
            development: WelcomeArt.development)
        if isResting { restingImage = image }
        return image
    }
}

/// The small e that heats up part by part as onboarding moves on.
public struct ProgressMark: View {
    private let heated: Int
    private let side: CGFloat
    @Environment(\.displayScale) private var displayScale

    public init(heated: Int, side: CGFloat) {
        self.heated = heated
        self.side = side
    }

    public var body: some View {
        Group {
            if let image = ProgressMarkCache.image(heated: heated, side: side, scale: displayScale) {
                Image(decorative: image, scale: displayScale)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Five small pictures at most, rendered once each.
@MainActor
private enum ProgressMarkCache {
    private struct Key: Hashable {
        let heated: Int
        let side: CGFloat
        let scale: CGFloat
    }

    private static var images: [Key: CGImage] = [:]

    static func image(heated: Int, side: CGFloat, scale: CGFloat) -> CGImage? {
        let key = Key(heated: heated, side: side, scale: scale)
        if let image = images[key] { return image }
        let image = HeatCanvas.render(
            ProgressMarkArt.strokes(heated: heated, side: side), size: CGSize(width: side, height: side),
            scale: scale, development: ProgressMarkArt.development)
        images[key] = image
        return image
    }
}
