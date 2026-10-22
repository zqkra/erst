import ErstUI
import SwiftUI

/// Tells the user that macOS applies a Screen Recording grant only after Erst reopens.
struct RelaunchNotice: View {
    let onReopen: () -> Void

    var body: some View {
        HStack(spacing: Spacing.large) {
            Text("macOS applies Screen Recording only after Erst reopens.")
                .erstStyle(Typography.body)
                .foregroundStyle(Color.erstSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onReopen) {
                Text("Quit and reopen").erstStyle(Typography.bodyMedium)
            }
            .prominentAction()
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.bottom, Spacing.huge)
    }
}
