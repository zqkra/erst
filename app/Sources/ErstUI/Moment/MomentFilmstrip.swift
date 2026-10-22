import ErstModel
import SwiftUI

/// Neighbor moments at the bottom of the screen.
public struct MomentFilmstrip: View {
    let model: MomentModel
    private let thumbnailWidthPoints: CGFloat = 104
    private let thumbnailHeightPoints: CGFloat = 65
    private let selectedBorderWidthPoints: CGFloat = 1.5
    private let borderWidthPoints: CGFloat = 1

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.small) {
                    ForEach(moments) { moment in
                        thumbnail(for: moment)
                            .id(moment.id)
                    }
                }
                .padding(.vertical, Spacing.xSmall)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
            .onChange(of: model.detail, initial: true) {
                proxy.scrollTo(model.currentMoment.id, anchor: .center)
            }
        }
        .frame(height: thumbnailHeightPoints + Spacing.xSmall + Spacing.xSmall)
    }

    private var moments: [Moment] {
        let neighbors = model.detail?.neighbors ?? []
        return (neighbors.filter { $0.id != model.currentMoment.id } + [model.currentMoment])
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private func thumbnail(for moment: Moment) -> some View {
        let selected = moment.id == model.currentMoment.id
        return Button {
            model.select(moment)
        } label: {
            Group {
                if let image = model.neighborImages[moment.id] {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.erstSurface
                }
            }
            .frame(width: thumbnailWidthPoints, height: thumbnailHeightPoints)
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                    .strokeBorder(
                        selected ? Color.erstButter : Color.erstHairline,
                        lineWidth: selected ? selectedBorderWidthPoints : borderWidthPoints)
            }
        }
        .buttonStyle(.plain)
        .help(ErstFormat.relativeDay(moment.capturedAt))
    }
}
