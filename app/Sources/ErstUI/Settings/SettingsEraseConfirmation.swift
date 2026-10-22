import SwiftUI

enum EraseConfirmationCopy {
    static let title = "Erase the last hour?"
    static let message = "This removes the screens and text Erst kept in the last hour."
}

/// Offscreen hosting cannot capture a native alert's separate window.
struct SettingsEraseConfirmation: View {
    let model: SettingsModel

    var body: some View {
        ZStack {
            Color.erstScrim
            VStack(spacing: Spacing.large) {
                AppBundleIcon(size: SettingsLayout.confirmationIconSize)
                Text(EraseConfirmationCopy.title)
                    .erstStyle(Typography.headline)
                    .foregroundStyle(Color.erstText)
                Text(EraseConfirmationCopy.message)
                    .erstStyle(Typography.body)
                    .foregroundStyle(Color.erstSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.small) {
                    Button("Cancel", role: .cancel) {
                        model.showEraseConfirmation = false
                    }
                    .glassAction()
                    Button(role: .destructive) {
                        model.confirmErase()
                    } label: {
                        Text("Erase").foregroundStyle(Color.erstCoral)
                    }
                    .glassAction()
                }
            }
            .padding(Spacing.xxLarge)
            .frame(width: SettingsLayout.confirmationWidth)
            .erstGlassSurface(cornerRadius: Radius.window)
        }
    }
}
