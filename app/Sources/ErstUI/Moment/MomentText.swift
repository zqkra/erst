import ErstModel
import SwiftUI

/// The recognized text, read the way a person would: sentences as paragraphs that reflow, short
/// stacked items such as a sidebar as a row of quiet chips, and lists with values as rows. Search
/// terms are marked, and the edges fade instead of showing a scroll bar.
public struct MomentText: View {
    let lines: [TextLine]
    let highlightedTerms: [String]

    private let lineSpacingPoints: CGFloat = 3
    private let topFadePoints: CGFloat = 12
    private let bottomFadePoints: CGFloat = 40

    public init(lines: [TextLine], highlightedTerms: [String]) {
        self.lines = lines
        self.highlightedTerms = highlightedTerms
    }

    public var body: some View {
        if lines.isEmpty {
            Text("No text on screen")
                .erstStyle(Typography.body)
                .foregroundStyle(Color.erstSecondary)
                .padding(.top, Spacing.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.large) {
                    ForEach(Array(lines.readingBlocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .text(let lines): paragraph(lines)
                        case .items(let items): MomentTextItems(items: items, terms: highlightedTerms)
                        case .entries(let entries):
                            MomentTextEntries(entries: entries, terms: highlightedTerms)
                        }
                    }
                }
                .padding(.top, topFadePoints)
                .padding(.bottom, bottomFadePoints)
            }
            .scrollIndicators(.never)
            .mask { edgeFade }
        }
    }

    /// Sentences in the reading tone. Detail lines, such as a name with its handle and time or a
    /// count under a title, are a step smaller and quieter, so the sentences lead.
    private func paragraph(_ lines: [ReadingLine]) -> some View {
        var text = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { text.append(AttributedString("\n")) }
            var part = TermHighlight.attributed(
                line.text, terms: highlightedTerms,
                base: line.isDetail ? .erstSecondary : .erstReadingText,
                markedFont: line.isDetail ? Typography.captionMedium.font : Typography.bodyMedium.font)
            if line.isDetail {
                for run in part.runs where run.font == nil {
                    part[run.range].font = Typography.caption.font
                }
            }
            text.append(part)
        }
        return Text(text)
            .erstStyle(Typography.body)
            .lineSpacing(lineSpacingPoints)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Opaque in the middle, clear at both edges, so text slides under them softly.
    private var edgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: topFadePoints)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: bottomFadePoints)
        }
    }
}

/// A sidebar, a menu, or a tab bar from the screen, as chips that wrap.
private struct MomentTextItems: View {
    let items: [String]
    let terms: [String]
    private let chipVerticalPaddingPoints: CGFloat = 3

    var body: some View {
        WrappingLayout(spacing: Spacing.xSmall, rowSpacing: Spacing.xSmall) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(
                    TermHighlight.attributed(
                        item, terms: terms, base: .erstReadingText,
                        markedFont: Typography.captionMedium.font)
                )
                .erstStyle(Typography.caption)
                .lineLimit(1)
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, chipVerticalPaddingPoints)
                .background(Capsule(style: .continuous).fill(Color.erstSurface))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A list whose rows pair a title with a value, laid out the way the screen had it: the title
/// leading, the value trailing in quiet figures, and the detail lines under the title.
private struct MomentTextEntries: View {
    let entries: [ReadingEntry]
    let terms: [String]
    private let titleDetailSpacingPoints: CGFloat = 2

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: titleDetailSpacingPoints) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                        Text(marked(entry.title, base: .erstReadingText, font: Typography.bodyMedium))
                            .erstStyle(Typography.body)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.small)
                        Text(marked(entry.value, base: .erstSecondary, font: Typography.captionMedium))
                            .erstStyle(Typography.caption)
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    ForEach(Array(entry.details.enumerated()), id: \.offset) { _, detail in
                        Text(marked(detail, base: .erstSecondary, font: Typography.captionMedium))
                            .erstStyle(Typography.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marked(_ text: String, base: Color, font: ErstTextStyle) -> AttributedString {
        TermHighlight.attributed(text, terms: terms, base: base, markedFont: font.font)
    }
}
