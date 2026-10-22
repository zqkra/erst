import ErstModel
import SwiftUI

/// Search over the timeline, grown out of the capsule.
///
/// One spring drives every part through `progress`, choreographed by `TimelineSearchMorph`. The
/// frame behind dims; a click on it closes the search.
struct TimelineSearchLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let presentation: TimelineSearchPresentation
    let service: any MemoryService
    let morph: TimelineSearchMorph
    let onOpenMoment: (Moment, [String]) -> Void

    private var progress: CGFloat { presentation.progress }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineStyle.searchDim
                .modifier(MorphDim(progress: progress))
                .contentShape(Rectangle())
                .onTapGesture { presentation.close() }
            Color.clear
                .modifier(MorphGlass(progress: progress, morph: morph, reduceMotion: reduceMotion))
                .allowsHitTesting(false)
            TimelineSearchCapsuleLabel(showsMark: false)
                .frame(width: morph.capsule.width, height: morph.capsule.height)
                .modifier(MorphCapsuleWords(progress: progress, morph: morph))
                .padding(.leading, morph.capsule.minX)
                .padding(.top, morph.capsule.minY)
                .allowsHitTesting(false)
            SearchScreen(
                service: service, surface: .host, onOpenMoment: onOpenMoment,
                onClose: { presentation.close() }
            )
            .frame(width: morph.panel.width, height: morph.panel.height)
            .contentShape(Rectangle())
            .modifier(MorphReveal(progress: progress, morph: morph, reduceMotion: reduceMotion))
            .padding(.leading, morph.panel.minX)
            .padding(.top, morph.panel.minY)
        }
        .overlayPreferenceValue(SearchQueryMarkKey.self) { anchor in
            GeometryReader { proxy in
                ErstMark()
                    .fill(Color.erstButter)
                    .modifier(
                        MorphMark(
                            progress: progress, morph: morph,
                            target: anchor.map { proxy[$0] } ?? morph.capsuleMark,
                            reduceMotion: reduceMotion)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            presentation.reducesMotion = reduceMotion
            presentation.expand()
        }
        .onChange(of: reduceMotion) { _, reduced in
            presentation.reducesMotion = reduced
        }
    }
}

/// Where every part of the morph is at a point of its progress, in the timeline surface's
/// coordinates.
///
/// Two phases share one spring, and the top edge never moves. First the capsule widens into the
/// panel's query band: its words fade out and the mark slides to the band's leading edge, where
/// the query field appears beside it. Then the band drops to the panel's full height and uncovers
/// the filters and results.
struct TimelineSearchMorph {
    let capsule: CGRect
    let capsuleMark: CGRect
    let panel: CGRect
    /// The panel's top band, which holds the query row: its padding, the row, and its padding.
    private let bandHeight: CGFloat

    private static let widening: ClosedRange<CGFloat> = 0...0.5
    private static let dropStart: CGFloat = 0.35
    private static let capsuleWordsFade: ClosedRange<CGFloat> = 0...0.2
    /// The search's parts arrive from when the band can hold the query field to the full panel.
    private static let contentArrival: ClosedRange<CGFloat> = 0.3...1

    init(surfaceSize: CGSize, panelSize: CGSize?) {
        let capsuleWidth = min(
            TimelineMetrics.searchWidth, surfaceSize.width * TimelineMetrics.searchWidthFraction)
        capsule = CGRect(
            x: (surfaceSize.width - capsuleWidth) / 2, y: TimelineMetrics.searchTopInset,
            width: capsuleWidth, height: TimelineMetrics.searchHeight)
        capsuleMark = CGRect(
            x: capsule.minX + TimelineMetrics.searchHorizontalPadding,
            y: capsule.midY - TimelineMetrics.searchMarkSize / 2,
            width: TimelineMetrics.searchMarkSize, height: TimelineMetrics.searchMarkSize)
        let fitted =
            panelSize
            ?? CGSize(
                width: surfaceSize.width * TimelineMetrics.searchPanelWidthFraction,
                height: surfaceSize.height * TimelineMetrics.searchPanelHeightFraction)
        let inset = TimelineMetrics.searchTopInset
        let width = max(capsuleWidth, min(fitted.width, surfaceSize.width - inset * 2))
        let height = max(capsule.height, min(fitted.height, surfaceSize.height - capsule.minY - inset))
        panel = CGRect(
            x: (surfaceSize.width - width) / 2, y: capsule.minY, width: width, height: height)
        bandHeight = min(max(TimelineMetrics.searchBandHeight, capsule.height), height)
    }

    func widening(at progress: CGFloat) -> CGFloat {
        progress.smoothstep(in: Self.widening)
    }

    /// 0 until the band starts to drop, 1 at the panel's height.
    func drop(at progress: CGFloat) -> CGFloat {
        max(0, (progress - Self.dropStart) / (1 - Self.dropStart))
    }

    func glass(at progress: CGFloat) -> CGRect {
        let widening = widening(at: progress)
        let width = widening.mix(capsule.width, panel.width)
        let height =
            capsule.height + (bandHeight - capsule.height) * widening
            + (panel.height - bandHeight) * drop(at: progress)
        return CGRect(x: panel.midX - width / 2, y: panel.minY, width: width, height: height)
    }

    /// The capsule's radius while it is a pill, the panel's once it is the band.
    func cornerRadius(at progress: CGFloat) -> CGFloat {
        widening(at: progress).mix(TimelineMetrics.searchCornerRadius, TimelineMetrics.dockCornerRadius)
    }

    /// From the capsule's tint and lift to the dock's, as it becomes a panel.
    func look(at progress: CGFloat) -> CGFloat {
        (widening(at: progress) + drop(at: progress).clampedToUnit) / 2
    }

    func mark(at progress: CGFloat, landingOn target: CGRect) -> CGRect {
        capsuleMark.morphed(to: target, by: widening(at: progress))
    }

    func capsuleWordsOpacity(at progress: CGFloat) -> CGFloat {
        1 - progress.smoothstep(in: Self.capsuleWordsFade)
    }

    /// The arrival the search's parts follow. Linear, because the spring already eases it.
    func contentArrival(at progress: CGFloat) -> CGFloat {
        let window = Self.contentArrival
        return ((progress - window.lowerBound) / (window.upperBound - window.lowerBound)).clampedToUnit
    }
}

// MARK: Morph pieces

/// The glass that grows from the capsule into the panel. With reduced motion it is the panel and
/// only fades.
private struct MorphGlass: ViewModifier, Animatable {
    var progress: CGFloat
    let morph: TimelineSearchMorph
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let rect = reduceMotion ? morph.panel : morph.glass(at: progress)
        let look = reduceMotion ? 1 : morph.look(at: progress)
        content
            .frame(width: rect.width, height: rect.height)
            .modifier(
                TimelineGlassModifier(
                    cornerRadius: reduceMotion
                        ? TimelineMetrics.dockCornerRadius : morph.cornerRadius(at: progress),
                    tint: TimelineStyle.searchTint.mix(with: TimelineStyle.surfaceTint, by: look),
                    fallback: TimelineStyle.searchTintFallback.mix(
                        with: TimelineStyle.surfaceTintFallback, by: look),
                    shadowRadius: look.mix(
                        TimelineMetrics.searchShadowRadius, TimelineMetrics.dockShadowRadius),
                    shadowY: look.mix(TimelineMetrics.searchShadowY, TimelineMetrics.dockShadowY),
                    shadowOpacity: look.mix(
                        TimelineMetrics.searchShadowOpacity, TimelineMetrics.dockShadowOpacity))
            )
            .opacity(reduceMotion ? progress.clampedToUnit : 1)
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// The search content, laid out once at the panel's size so nothing reflows, clipped to the
/// growing glass. Its parts arrive in reading order once the band can hold the query field.
private struct MorphReveal: ViewModifier, Animatable {
    var progress: CGFloat
    let morph: TimelineSearchMorph
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let panel = morph.panel
        let rect = (reduceMotion ? panel : morph.glass(at: progress))
            .offsetBy(dx: -panel.minX, dy: -panel.minY)
        let radius = reduceMotion ? TimelineMetrics.dockCornerRadius : morph.cornerRadius(at: progress)
        content
            .environment(
                \.erstArrivalProgress,
                reduceMotion ? progress.clampedToUnit : morph.contentArrival(at: progress)
            )
            .mask(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .frame(width: max(0, rect.width), height: max(0, rect.height))
                    .offset(x: rect.minX, y: rect.minY)
            }
    }
}

/// The capsule's words, fading out as the capsule starts to widen.
private struct MorphCapsuleWords: ViewModifier, Animatable {
    var progress: CGFloat
    let morph: TimelineSearchMorph

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(morph.capsuleWordsOpacity(at: progress))
    }
}

/// The dim over the frame, which follows the spring without its bounce.
private struct MorphDim: ViewModifier, Animatable {
    var progress: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(progress.clampedToUnit)
    }
}

/// The butter mark, sliding from the capsule to the query field as the capsule widens.
private struct MorphMark: ViewModifier, Animatable {
    var progress: CGFloat
    let morph: TimelineSearchMorph
    let target: CGRect
    let reduceMotion: Bool

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let rect = reduceMotion ? target : morph.mark(at: progress, landingOn: target)
        content
            .frame(width: rect.width, height: rect.height)
            .opacity(reduceMotion ? progress.clampedToUnit : 1)
            .offset(x: rect.minX, y: rect.minY)
    }
}

extension CGFloat {
    fileprivate var clampedToUnit: CGFloat { Swift.min(Swift.max(self, 0), 1) }

    /// Self as the fraction from `start` to `end`.
    fileprivate func mix(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
        start + (end - start) * self
    }

    /// 0 before the window, 1 after it, and an eased ramp inside it.
    fileprivate func smoothstep(in window: ClosedRange<CGFloat>) -> CGFloat {
        let span = window.upperBound - window.lowerBound
        guard span > 0 else { return self >= window.upperBound ? 1 : 0 }
        let t = ((self - window.lowerBound) / span).clampedToUnit
        return t * t * (3 - 2 * t)
    }
}

extension CGRect {
    /// The rectangle `fraction` of the way to `target`.
    fileprivate func morphed(to target: CGRect, by fraction: CGFloat) -> CGRect {
        CGRect(
            x: fraction.mix(minX, target.minX), y: fraction.mix(minY, target.minY),
            width: fraction.mix(width, target.width), height: fraction.mix(height, target.height))
    }
}
