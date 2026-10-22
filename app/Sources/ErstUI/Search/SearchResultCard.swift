import ErstModel
import SwiftUI

/// One moment result: frame, title, time, and the matched line with its terms marked.
///
/// Selection is a quiet platter under the whole card, not a ring around it, so the frames stay
/// the loudest thing in the grid. The pointer gets a lighter platter, and a press settles the
/// card a little.
public struct SearchResultCard: View {
    let hit: SearchHit
    let model: SearchModel
    let isSelected: Bool
    let onOpen: () -> Void

    private let captionLineLimit = 2
    private let titleLineLimit = 1

    public init(
        hit: SearchHit,
        model: SearchModel,
        isSelected: Bool,
        onOpen: @escaping () -> Void
    ) {
        self.hit = hit
        self.model = model
        self.isSelected = isSelected
        self.onOpen = onOpen
    }

    public var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                SearchThumbnail(hit: hit, image: model.images[hit.moment.id])
                titleRow
                caption
                    .lineLimit(captionLineLimit)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.small)
            // Fill the row height so every platter in a row is as tall as the tallest card.
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(SearchCardStyle(platter: platter))
        .onHover { model.hover(hit, inside: $0) }
        .task(id: hit.id) {
            await model.loadThumbnail(for: hit)
        }
    }

    private var platter: Color {
        if isSelected { return .erstCardSelected }
        return model.hoveredHitID == hit.id ? .erstCardHover : .clear
    }

    @ViewBuilder
    private var caption: some View {
        if let line = hit.matchedLines.first?.text {
            Text(
                TermHighlight.attributed(
                    line, terms: model.highlightTerms, base: .erstReadingText,
                    markedFont: Typography.captionMedium.font)
            )
            .erstStyle(Typography.caption)
        } else {
            Text(hit.moment.app.name)
                .erstStyle(Typography.caption)
                .foregroundStyle(Color.erstSecondary)
        }
    }

    private var titleText: String {
        WindowTitle.clean(hit.moment.windowTitle, appName: hit.moment.app.name)
            ?? hit.moment.app.name
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Text(titleText)
                .erstStyle(Typography.bodyMedium)
                .foregroundStyle(Color.erstText)
                .lineLimit(titleLineLimit)
                .truncationMode(.tail)
            Spacer(minLength: Spacing.small)
            Text(ErstFormat.relativeDay(hit.lastSeen))
                .erstStyle(Typography.caption)
                .foregroundStyle(Color.erstSecondary)
                .lineLimit(titleLineLimit)
                .fixedSize()
        }
    }
}

/// The card's platter, and a small settle while it is pressed.
private struct SearchCardStyle: ButtonStyle {
    let platter: Color
    private let pressedScale: CGFloat = 0.98
    private let pressAnimation = Animation.easeOut(duration: 0.12)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(platter)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(pressAnimation, value: configuration.isPressed)
    }
}
