import SwiftUI

/// The floating entrance to search, centered over the captured frame.
public struct TimelineSearchCapsule: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            TimelineSearchCapsuleLabel(showsMark: true)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(height: TimelineMetrics.searchHeight)
        .timelineSearchSurface()
        .help("Search everything you saw")
        .accessibilityLabel("Search everything you saw")
    }
}

/// The capsule's mark, placeholder, and shortcut. The search morph draws it without the mark,
/// which flies on its own, while the words fade out.
struct TimelineSearchCapsuleLabel: View {
    let showsMark: Bool

    var body: some View {
        HStack(spacing: TimelineMetrics.searchGap) {
            ErstMark()
                .fill(Color.erstButter)
                .frame(width: TimelineMetrics.searchMarkSize, height: TimelineMetrics.searchMarkSize)
                .opacity(showsMark ? 1 : 0)
            Text("Search everything you saw")
                .erstStyle(TimelineType.placeholder)
                .foregroundStyle(TimelineStyle.placeholder)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\u{2318}K")
                .erstStyle(TimelineType.shortcut)
                .foregroundStyle(TimelineStyle.shortcut)
        }
        .padding(.horizontal, TimelineMetrics.searchHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
