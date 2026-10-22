import ErstModel
import SwiftUI

/// One kept frame with its inspector, live text, and nearby moments.
public struct MomentScreen: View {
    @StateObject private var model: MomentModel
    private let onOpenTimeline: (Date) -> Void
    private let onClose: () -> Void
    private let inspectorWidthPoints: CGFloat = 360
    private let placeholderMarkSizePoints: CGFloat = 36
    private let frameBorderWidthPoints: CGFloat = 1

    public init(
        service: any MemoryService,
        moment: Moment,
        highlightedTerms: [String] = [],
        onOpenTimeline: @escaping (Date) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(
            wrappedValue: MomentModel(
                service: service,
                moment: moment,
                highlightedTerms: highlightedTerms
            )
        )
        self.onOpenTimeline = onOpenTimeline
        self.onClose = onClose
    }

    /// Shows a moment for a model the caller already owns, for a chosen inspector state.
    public init(
        model: MomentModel,
        onOpenTimeline: @escaping (Date) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: model)
        self.onOpenTimeline = onOpenTimeline
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: Spacing.large) {
            MomentHeader(model: model, onOpenTimeline: onOpenTimeline, onClose: onClose)
                .erstArrival(0, from: .above, blurs: false)
            HStack(alignment: .top, spacing: Spacing.xLarge) {
                VStack(spacing: Spacing.large) {
                    frame
                    MomentFilmstrip(model: model)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .erstArrival(1, from: .center, blurs: false)
                MomentInspector(model: model)
                    .frame(width: inspectorWidthPoints)
                    .frame(maxHeight: .infinity)
                    .erstArrival(2, from: .trailing, blurs: false)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .erstArrivalStage()
        .erstGlassSurface(cornerRadius: Radius.panel)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .task {
            Typography.registerFonts()
            await model.load()
        }
        .onDisappear { model.cancelLoading() }
        .onExitCommand(perform: onClose)
        .sheet(
            isPresented: Binding(
                get: { model.reminderPickerPresented },
                set: { model.reminderPickerPresented = $0 }
            )
        ) {
            ReminderPicker(model: model)
        }
    }

    /// The marks sit on the aspect-fit image, the way the image view centers it.
    private func marks(on image: CGImage) -> some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / CGFloat(image.width), proxy.size.height / CGFloat(image.height))
            TextMatchMarks(boxes: model.matchedBoxes)
                .frame(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var frame: some View {
        Group {
            if let image = model.image {
                LiveTextImage(image: image)
                    .overlay { marks(on: image) }
            } else {
                ZStack {
                    Color.erstSurface
                    ErstMark()
                        .fill(Color.erstButter)
                        .frame(width: placeholderMarkSizePoints, height: placeholderMarkSizePoints)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.frame, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.frame, style: .continuous)
                .strokeBorder(Color.erstHairline, lineWidth: frameBorderWidthPoints)
        }
    }
}
