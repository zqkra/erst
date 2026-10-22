import SwiftUI

/// What sits at an onboarding row's trailing edge.
enum OnboardingRowTrailing {
    /// Done, in butter with a check.
    case done(String)
    /// A button the user can press.
    case action(String, () -> Void)
    /// A quiet note when there is nothing to do.
    case note(String)
    /// Nothing: the row only explains.
    case empty
}

/// One thing onboarding asks for, on a quiet platter: a permission, or an agent to connect.
struct OnboardingRow<Leading: View>: View {
    private let leading: Leading
    private let title: String
    private let subtitle: String
    private let trailing: OnboardingRowTrailing
    private let isDimmed: Bool

    init(
        title: String, subtitle: String, trailing: OnboardingRowTrailing, isDimmed: Bool = false,
        @ViewBuilder leading: () -> Leading
    ) {
        self.leading = leading()
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.isDimmed = isDimmed
    }

    var body: some View {
        HStack(spacing: Spacing.large) {
            leading
            VStack(alignment: .leading, spacing: Spacing.xSmall / 2) {
                Text(title)
                    .erstStyle(Typography.headline)
                    .foregroundStyle(isDimmed ? Color.erstSecondary : Color.erstText)
                Text(subtitle)
                    .erstStyle(Typography.body)
                    .foregroundStyle(Color.erstSecondary)
            }
            Spacer(minLength: Spacing.small)
            trailingView
                .frame(width: OnboardingLayout.rowTrailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.large)
        .frame(height: OnboardingLayout.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.erstSurface)
        }
    }

    @ViewBuilder private var trailingView: some View {
        switch trailing {
        case .done(let label):
            HStack(spacing: Spacing.small) {
                Image(systemName: "checkmark.circle.fill")
                    .font(Typography.icon.font)
                    .foregroundStyle(Color.erstButter)
                Text(label)
                    .erstStyle(Typography.bodyMedium)
                    .foregroundStyle(Color.erstText)
            }
        case .action(let label, let perform):
            Button(action: perform) {
                Text(label).erstStyle(Typography.bodyMedium)
            }
            .glassAction()
        case .note(let label):
            Text(label)
                .erstStyle(Typography.bodyMedium)
                .foregroundStyle(Color.erstSecondary)
        case .empty:
            EmptyView()
        }
    }
}

extension OnboardingRow where Leading == RowSymbol {
    /// A row led by a symbol, for what has no app icon of its own.
    init(
        symbol: String, title: String, subtitle: String, trailing: OnboardingRowTrailing,
        isDimmed: Bool = false
    ) {
        self.init(title: title, subtitle: subtitle, trailing: trailing, isDimmed: isDimmed) {
            RowSymbol(symbol: symbol, isDimmed: isDimmed)
        }
    }
}
