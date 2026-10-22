import ErstModel
import SwiftUI

/// Who draws the glass around search. The parts arrive in reading order: on the panel after its
/// glass, and over the timeline as the capsule's morph drops.
public enum SearchSurface: Sendable {
    /// Search draws its own floating glass panel.
    case panel
    /// A host draws the glass and the query mark, as the timeline does when its capsule grows
    /// into search.
    case host
}

/// The floating search surface.
public struct SearchScreen: View {
    @StateObject private var model: SearchModel
    @FocusState private var isQueryFocused: Bool

    private let surface: SearchSurface
    private let onOpenMoment: (Moment, [String]) -> Void
    private let onClose: () -> Void
    private let dividerHeightPoints: CGFloat = 1

    public init(
        service: any MemoryService,
        query: String = "",
        surface: SearchSurface = .panel,
        onOpenMoment: @escaping (Moment, [String]) -> Void = { _, _ in },
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: SearchModel(service: service, query: query))
        self.surface = surface
        self.onOpenMoment = onOpenMoment
        self.onClose = onClose
    }

    /// Shows a screen for a model the caller already owns, so a snapshot can wait for its search.
    public init(
        model: SearchModel,
        surface: SearchSurface = .panel,
        onOpenMoment: @escaping (Moment, [String]) -> Void = { _, _ in },
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: model)
        self.surface = surface
        self.onOpenMoment = onOpenMoment
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SearchQueryRow(model: model, isFocused: $isQueryFocused, showsMark: surface == .panel)
                .erstArrival(1, from: .above, blurs: false)
            Rectangle()
                .fill(Color.erstHairline)
                .frame(height: dividerHeightPoints)
                .padding(.top, Spacing.large)
                .erstArrival(2, blurs: false)
            SearchFilterRow(model: model)
                .padding(.top, Spacing.large)
                .erstArrival(3, blurs: false)
            SearchResultGrid(model: model, onOpen: open)
                .padding(.top, Spacing.large)
                .erstArrival(4, blurs: false)
        }
        .padding(Spacing.xxLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(SearchSurfaceModifier(surface: surface))
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .task {
            Typography.registerFonts()
            isQueryFocused = true
            await model.loadFilters()
        }
        .task(id: model.searchKey) {
            guard !model.trimmedQuery.isEmpty else {
                await model.loadRecent()
                return
            }
            try? await Task.sleep(for: .milliseconds(SearchModel.searchDebounceMilliseconds))
            guard !Task.isCancelled else { return }
            await model.search()
        }
        .searchKeyboard(model: model, onOpen: open, onClose: onClose)
    }

    private func open(_ hit: SearchHit) {
        model.select(hit)
        onOpenMoment(hit.moment, model.highlightTerms)
    }
}

private struct SearchSurfaceModifier: ViewModifier {
    let surface: SearchSurface

    func body(content: Content) -> some View {
        switch surface {
        case .panel:
            content
                .erstGlassSurface(cornerRadius: Radius.panel)
                .erstArrival(0, from: .center, blurs: false)
                .erstArrivalStage()
        case .host: content
        }
    }
}
