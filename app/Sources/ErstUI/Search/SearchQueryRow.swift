import SwiftUI

/// The mark and the query field.
public struct SearchQueryRow: View {
    let model: SearchModel
    var isFocused: FocusState<Bool>.Binding
    /// False when a host draws the mark itself, as the timeline's search morph does.
    var showsMark = true
    private let markSizePoints: CGFloat = 22

    public var body: some View {
        HStack(spacing: Spacing.medium) {
            ErstMark()
                .fill(Color.erstButter)
                .frame(width: markSizePoints, height: markSizePoints)
                .opacity(showsMark ? 1 : 0)
                .anchorPreference(key: SearchQueryMarkKey.self, value: .bounds) { $0 }
            TextField(
                "Search everything you saw",
                text: Binding(get: { model.query }, set: { model.query = $0 })
            )
            .textFieldStyle(.plain)
            .font(Typography.query.font)
            .foregroundStyle(Color.erstText)
            .focused(isFocused)
        }
    }
}

/// Where the query row's mark sits, so a host can land its own mark on it.
struct SearchQueryMarkKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
