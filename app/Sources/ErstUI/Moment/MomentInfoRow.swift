import SwiftUI

/// A label and value row in the inspector.
public struct MomentInfoRow: View {
    private let label: String
    private let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Text(label)
                .erstStyle(Typography.body)
                .foregroundStyle(Color.erstSecondary)
            Spacer(minLength: Spacing.small)
            Text(value)
                .erstStyle(Typography.bodyMedium)
                .foregroundStyle(Color.erstText)
                .multilineTextAlignment(.trailing)
        }
    }
}
