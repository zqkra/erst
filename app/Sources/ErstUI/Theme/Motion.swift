import Combine
import SwiftUI

/// How Erst's surfaces arrive.
///
/// A surface assembles in reading order. Its parts start a few hundredths of a second apart, and
/// each rises a few points out of a blur that clears as it settles, which reads as motion blur.
/// One critically damped spring drives the whole surface, so parts never overshoot and never
/// drift out of order. With Reduce Motion the parts only fade.
public enum Motion {
    /// One spring per arrival. Critically damped, because a click or a shortcut carries no
    /// momentum to overshoot with.
    public static let arrive = Animation.spring(duration: 0.42, bounce: 0)
    /// Reduce Motion: a short fade.
    public static let reducedArrive = Animation.easeOut(duration: 0.16)
    /// How far apart in the surface's progress two neighboring parts start. On `arrive` that is
    /// about 17 ms.
    static let stagger: CGFloat = 0.08
    /// The share of the surface's progress one part takes to settle.
    static let partSpan: CGFloat = 0.6
    /// The blur a part arrives out of, in points.
    static let blur: CGFloat = 8
    /// How far a part travels as it arrives, in points.
    static let travel: CGFloat = 12
    /// The scale a centered part grows from.
    static let centeredScale: CGFloat = 0.98

    /// Snapshots hold every arrival at this progress instead of playing it. Nil plays arrivals.
    @MainActor public static var heldArrival: CGFloat?

    /// A part's own progress inside its surface's: it starts `order` steps late and takes
    /// `partSpan` of the whole. Orders past the last one that fits finish with that one.
    static func fraction(of progress: CGFloat, order: Int) -> CGFloat {
        let lastOrder = Int(((1 - partSpan) / stagger).rounded(.down))
        let start = CGFloat(min(max(order, 0), lastOrder)) * stagger
        return min(max((progress - start) / partSpan, 0), 1)
    }
}

/// The side a part arrives from. Parts near an edge come from that edge, a part in the middle
/// grows a little, and a part that fills its surface only comes into focus.
public enum ArrivalEdge: Sendable {
    case above, below, leading, trailing, center, inPlace
}

private struct ArrivalProgressKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// How far the enclosing surface has arrived, 0 to 1. Outside a stage everything has arrived.
    var erstArrivalProgress: CGFloat {
        get { self[ArrivalProgressKey.self] }
        set { self[ArrivalProgressKey.self] = newValue }
    }
}

extension View {
    /// Plays the arrival of the parts inside, once, when the surface first appears. A new `replay`
    /// value plays it again, for content that is replaced as a whole.
    public func erstArrivalStage<Key: Equatable>(replay key: Key) -> some View {
        modifier(ArrivalStage(key: key))
    }

    /// Plays the arrival of the parts inside once, when the surface first appears.
    public func erstArrivalStage() -> some View {
        modifier(ArrivalStage(key: 0))
    }

    /// One part of a surface, arriving `order` steps after the first. Parts that host AppKit views
    /// or glass pass `blurs: false`, because SwiftUI cannot blur them cheaply.
    public func erstArrival(
        _ order: Int, from edge: ArrivalEdge = .below, blurs: Bool = true
    ) -> some View {
        modifier(ArrivalPart(order: order, edge: edge, blurs: blurs))
    }
}

private struct ArrivalStage<Key: Equatable>: ViewModifier {
    let key: Key
    @StateObject private var state = ArrivalState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.erstArrivalProgress, state.progress)
            .onAppear { state.play(reduceMotion: reduceMotion, replaying: false) }
            .onChange(of: key) { _, _ in state.play(reduceMotion: reduceMotion, replaying: true) }
    }
}

@MainActor
private final class ArrivalState: ObservableObject {
    @Published private(set) var progress: CGFloat
    private var hasPlayed = false

    init() {
        progress = Motion.heldArrival ?? 0
    }

    /// The first appearance plays once; a surface shown again keeps its arrived parts.
    func play(reduceMotion: Bool, replaying: Bool) {
        guard Motion.heldArrival == nil, replaying || !hasPlayed else { return }
        hasPlayed = true
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }
        withAnimation(reduceMotion ? Motion.reducedArrive : Motion.arrive) { progress = 1 }
    }
}

private struct ArrivalPart: ViewModifier {
    let order: Int
    let edge: ArrivalEdge
    let blurs: Bool
    @Environment(\.erstArrivalProgress) private var progress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.modifier(
            ArrivalEffect(
                progress: progress, order: order, edge: edge, blurs: blurs,
                reduceMotion: reduceMotion))
    }
}

/// Interpolated every frame by the stage's spring, without rebuilding the part.
private struct ArrivalEffect: ViewModifier, Animatable {
    var progress: CGFloat
    let order: Int
    let edge: ArrivalEdge
    let blurs: Bool
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let fraction = Motion.fraction(of: progress, order: order)
        let moves = !reduceMotion
        let remaining = moves ? 1 - fraction : 0
        content
            .scaleEffect(edge == .center ? 1 - (1 - Motion.centeredScale) * remaining : 1)
            .blur(radius: blurs ? Motion.blur * remaining : 0)
            .offset(offset(remaining: remaining))
            .opacity(fraction)
    }

    private func offset(remaining: CGFloat) -> CGSize {
        let distance = Motion.travel * remaining
        switch edge {
        case .above: return CGSize(width: 0, height: -distance)
        case .below: return CGSize(width: 0, height: distance)
        case .leading: return CGSize(width: -distance, height: 0)
        case .trailing: return CGSize(width: distance, height: 0)
        case .center, .inPlace: return .zero
        }
    }
}
