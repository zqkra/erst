import SwiftUI

/// One flat action inside the dock's action capsule.
struct TimelineActionButton: View {
    let symbol: String
    let help: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: TimelineMetrics.actionGlyphSize, weight: .regular))
                .foregroundStyle(TimelineStyle.actionGlyph.opacity(isEnabled ? 1 : 0.4))
                .frame(
                    width: TimelineMetrics.actionButtonWidth,
                    height: TimelineMetrics.actionButtonHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
