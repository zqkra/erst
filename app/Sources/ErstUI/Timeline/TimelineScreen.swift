import ErstModel
import SwiftUI

/// The floating timeline surface over the desktop.
///
/// Search opens inside it: the capsule grows into the search panel over the dimmed frame, and
/// Escape shrinks it back into the capsule.
public struct TimelineScreen: View {
    @StateObject private var model: TimelineModel
    @StateObject private var search: TimelineSearchPresentation
    @FocusState private var isFocused: Bool

    private let onClose: () -> Void
    private let onOpenMoment: (Moment) -> Void
    private let onOpenSearchResult: (Moment, [String]) -> Void

    public init(
        service: any MemoryService,
        now: Date = Date(),
        search: TimelineSearchPresentation = TimelineSearchPresentation(),
        onClose: @escaping () -> Void = {},
        onOpenMoment: @escaping (Moment) -> Void = { _ in },
        onOpenSearchResult: @escaping (Moment, [String]) -> Void = { _, _ in }
    ) {
        _model = StateObject(wrappedValue: TimelineModel(service: service, now: now))
        _search = StateObject(wrappedValue: search)
        self.onClose = onClose
        self.onOpenMoment = onOpenMoment
        self.onOpenSearchResult = onOpenSearchResult
    }

    /// Builds the screen around a model that is already configured, for a chosen zoom state.
    public init(
        model: TimelineModel,
        search: TimelineSearchPresentation = TimelineSearchPresentation(),
        onClose: @escaping () -> Void = {},
        onOpenMoment: @escaping (Moment) -> Void = { _ in },
        onOpenSearchResult: @escaping (Moment, [String]) -> Void = { _, _ in }
    ) {
        _model = StateObject(wrappedValue: model)
        _search = StateObject(wrappedValue: search)
        self.onClose = onClose
        self.onOpenMoment = onOpenMoment
        self.onOpenSearchResult = onOpenSearchResult
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                frameLayer
                    .transaction { $0.disablesAnimations = true }
                TimelineBackdrop()
                if model.isEmpty {
                    TimelineEmptyState()
                } else {
                    overlay(size: proxy.size)
                }
                if search.isPresented {
                    TimelineSearchLayer(
                        presentation: search,
                        service: model.service,
                        morph: TimelineSearchMorph(
                            surfaceSize: proxy.size, panelSize: search.panelSize),
                        onOpenMoment: onOpenSearchResult
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .erstArrivalStage()
        .erstGlassSurface(cornerRadius: Radius.panel)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            Typography.registerFonts()
            isFocused = true
        }
        .onChange(of: search.isPresented) { _, presented in
            if !presented { isFocused = true }
        }
        .task {
            await model.load()
        }
        .modifier(
            TimelineKeyboard(
                model: model, search: search, onOpenMoment: onOpenMoment, onClose: onClose))
    }

    /// The remembered frame comes into focus whenever a new one arrives after none, on open and
    /// after a jump. Scrubbing swaps frames in place.
    private var frameLayer: some View {
        ZStack {
            Color.erstGround
            if let image = model.image {
                AspectFillImage(image: image)
                    .erstArrival(0, from: .inPlace)
            }
        }
        .erstArrivalStage(replay: model.image == nil)
    }

    /// The capsule hides while search is open, because the search layer draws its shape. The dock
    /// sinks and fades with the same spring, outside the timeline's disabled animations.
    private func overlay(size: CGSize) -> some View {
        VStack(spacing: 0) {
            TimelineSearchCapsule(action: { search.open() })
                .frame(
                    width: min(
                        TimelineMetrics.searchWidth,
                        size.width * TimelineMetrics.searchWidthFraction)
                )
                .padding(.top, TimelineMetrics.searchTopInset)
                .opacity(search.isPresented ? 0 : 1)
                .transaction { $0.disablesAnimations = true }
                .erstArrival(0, from: .above, blurs: false)
            Spacer(minLength: 0)
            TimelineDock(model: model, onOpenMoment: onOpenMoment)
                .transaction { $0.disablesAnimations = true }
                .erstArrival(1, from: .below, blurs: false)
                .offset(y: search.progress * TimelineMetrics.searchDockSlide)
                .opacity(1 - min(max(search.progress, 0), 1))
                .padding(.horizontal, TimelineMetrics.dockInset)
                .padding(.bottom, TimelineMetrics.dockInset)
        }
        .task(id: model.hasLoaded) {
            guard model.hasLoaded else { return }
            model.applyInitialScale(trackWidth: TimelineMetrics.trackWidth(surfaceWidth: size.width))
        }
    }
}
