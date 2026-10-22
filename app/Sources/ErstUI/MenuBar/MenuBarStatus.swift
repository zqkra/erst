import ErstModel
import SwiftUI

/// The recorder state under the title, shown only when it is not recording normally.
public struct MenuBarStatus: View {
    let status: RecorderStatus
    let onFixPermission: () -> Void

    public init(status: RecorderStatus, onFixPermission: @escaping () -> Void) {
        self.status = status
        self.onFixPermission = onFixPermission
    }

    public var body: some View {
        switch status {
        case .recording:
            EmptyView()
        case .paused(let until):
            Text(until.map { "Paused until \(ErstFormat.shortClock($0))" } ?? "Paused")
                .erstStyle(Typography.caption)
                .foregroundStyle(Color.erstSecondary)
        case .needsPermission:
            Button(action: onFixPermission) {
                Text("Needs permission").erstStyle(Typography.captionMedium)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.erstButter)
        case .stopped:
            Text("Paused")
                .erstStyle(Typography.caption)
                .foregroundStyle(Color.erstSecondary)
        }
    }
}
