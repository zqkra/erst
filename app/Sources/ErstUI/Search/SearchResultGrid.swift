import ErstModel
import SwiftUI

/// The grid of matching moments, or of recent visits before anything is typed, scrolled inside the panel.
public struct SearchResultGrid: View {
    let model: SearchModel
    let onOpen: (SearchHit) -> Void

    /// Top aligned so a card whose matched line wraps does not lift its row neighbors.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Spacing.large, alignment: .top),
        count: SearchModel.resultColumnCount
    )

    public init(model: SearchModel, onOpen: @escaping (SearchHit) -> Void) {
        self.model = model
        self.onOpen = onOpen
    }

    public var body: some View {
        Group {
            if model.trimmedQuery.isEmpty {
                if model.recent.isEmpty {
                    Color.clear
                } else {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        Text("Recent")
                            .erstStyle(Typography.caption)
                            .foregroundStyle(Color.erstSecondary)
                        grid
                    }
                }
            } else if model.hasSearched && model.hits.isEmpty {
                Text("No matches")
                    .erstStyle(Typography.body)
                    .foregroundStyle(Color.erstSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.xxLarge) {
                    ForEach(Array(model.displayedHits.enumerated()), id: \.element.id) { index, hit in
                        SearchResultCard(
                            hit: hit,
                            model: model,
                            isSelected: hit.id == model.selectedHitID,
                            onOpen: { onOpen(hit) }
                        )
                        .id(hit.id)
                        .erstArrival(index)
                    }
                }
                .padding(.bottom, Spacing.medium)
                // Recent visits and matches each cascade in when they replace the other. Results
                // refined while typing swap in place, because they change on every keystroke.
                .erstArrivalStage(replay: model.trimmedQuery.isEmpty)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.selectedHitID) { _, identifier in
                guard let identifier else { return }
                proxy.scrollTo(identifier, anchor: .center)
            }
        }
    }
}
