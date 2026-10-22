import SwiftUI

/// A circular glass icon button with a solid fallback for snapshots.
public struct CircleGlassButton: View {
    @Environment(\.erstOpaquePanels) private var opaquePanels
    private let symbol: String
    private let help: String
    private let isEnabled: Bool
    private let action: () -> Void

    public init(symbol: String, help: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typography.icon.font)
                .frame(width: ControlMetrics.circleButtonPoints, height: ControlMetrics.circleButtonPoints)
                .background {
                    if opaquePanels {
                        Circle().fill(Color.erstSurface)
                    }
                }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help(help)
        .disabled(!isEnabled)
    }
}
