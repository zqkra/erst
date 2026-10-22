import SwiftUI

/// The stage size and panel sizes the overlay host uses on a 1440 by 900 desktop.
enum SnapshotStageMetrics {
    static let stageWidthPoints: CGFloat = 1440
    static let stageHeightPoints: CGFloat = 900
    static let searchWidthFraction: CGFloat = 0.65
    static let searchHeightFraction: CGFloat = 0.65
    static let searchMaximumWidthPoints: CGFloat = 1080
    static let searchMaximumHeightPoints: CGFloat = 720
    static let panelWidthFraction: CGFloat = 0.8
    static let panelHeightFraction: CGFloat = 0.9

    static var searchPanelSize: CGSize {
        CGSize(
            width: min(stageWidthPoints * searchWidthFraction, searchMaximumWidthPoints),
            height: min(stageHeightPoints * searchHeightFraction, searchMaximumHeightPoints)
        )
    }

    static var largePanelSize: CGSize {
        CGSize(
            width: stageWidthPoints * panelWidthFraction,
            height: stageHeightPoints * panelHeightFraction
        )
    }
}

/// Shows an overlay screen at its hosted size over a neutral desktop and the dim layer.
struct SnapshotStage<Content: View>: View {
    let panelSize: CGSize
    private let content: Content

    init(panelSize: CGSize, @ViewBuilder content: () -> Content) {
        self.panelSize = panelSize
        self.content = content()
    }

    var body: some View {
        ZStack {
            SampleDesktop()
            Color.erstScrim
            content
                .frame(width: panelSize.width, height: panelSize.height)
        }
        .frame(
            width: SnapshotStageMetrics.stageWidthPoints,
            height: SnapshotStageMetrics.stageHeightPoints
        )
        .clipped()
    }
}

/// A gradient-free desktop stand-in so the floating surface has something behind it.
private struct SampleDesktop: View {
    private let desktopColor = Color(.sRGB, red: 0.34, green: 0.36, blue: 0.39, opacity: 1)
    private let firstWindowColor = Color(.sRGB, red: 0.41, green: 0.43, blue: 0.46, opacity: 1)
    private let secondWindowColor = Color(.sRGB, red: 0.38, green: 0.4, blue: 0.43, opacity: 1)
    private let sidebarColor = Color(.sRGB, red: 0.46, green: 0.48, blue: 0.51, opacity: 1)
    private let panelColor = Color(.sRGB, red: 0.52, green: 0.54, blue: 0.57, opacity: 1)
    private let windowRadiusPoints: CGFloat = 18
    private let panelRadiusPoints: CGFloat = 12

    private let firstWindowRect = CGRect(x: 0.05, y: 0.131, width: 0.428, height: 0.693)
    private let sidebarRect = CGRect(x: 0.061, y: 0.149, width: 0.106, height: 0.658)
    private let pageRect = CGRect(x: 0.179, y: 0.149, width: 0.288, height: 0.367)
    private let pageFooterRect = CGRect(x: 0.179, y: 0.536, width: 0.288, height: 0.271)
    private let secondWindowRect = CGRect(x: 0.596, y: 0.262, width: 0.329, height: 0.476)
    private let secondHeaderRect = CGRect(x: 0.61, y: 0.284, width: 0.301, height: 0.102)

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(desktopColor)
            )
            fill(context, firstWindowRect, firstWindowColor, windowRadiusPoints, in: size)
            fill(context, sidebarRect, sidebarColor, panelRadiusPoints, in: size)
            fill(context, pageRect, panelColor, panelRadiusPoints, in: size)
            fill(context, pageFooterRect, secondWindowColor, panelRadiusPoints, in: size)
            fill(context, secondWindowRect, secondWindowColor, windowRadiusPoints, in: size)
            fill(context, secondHeaderRect, panelColor, panelRadiusPoints, in: size)
        }
        .accessibilityHidden(true)
    }

    private func fill(
        _ context: GraphicsContext,
        _ normalizedRect: CGRect,
        _ color: Color,
        _ radius: CGFloat,
        in size: CGSize
    ) {
        let rect = CGRect(
            x: normalizedRect.minX * size.width,
            y: normalizedRect.minY * size.height,
            width: normalizedRect.width * size.width,
            height: normalizedRect.height * size.height
        )
        context.fill(
            Path(roundedRect: rect, cornerRadius: radius),
            with: .color(color)
        )
    }
}
