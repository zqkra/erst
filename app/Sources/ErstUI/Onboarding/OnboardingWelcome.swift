import Combine
import SwiftUI

/// The first thing Erst shows: its mark on a horizon, the echoes rising out of it, and one line.
/// The copy arrives once the echoes are on their way.
struct OnboardingWelcome: View {
    let onStart: () -> Void
    @StateObject private var model = WelcomeCopyModel()

    var body: some View {
        ZStack(alignment: .top) {
            WelcomeEcho()
            if model.showsCopy {
                copy
                    .padding(.top, OnboardingLayout.welcomeCopyTop)
                    .erstArrivalStage()
            }
        }
        .frame(width: OnboardingLayout.windowWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .task { await model.reveal() }
    }

    private var copy: some View {
        VStack(spacing: Spacing.medium) {
            Text(OnboardingStep.welcome.title)
                .erstStyle(Typography.welcomeTitle)
                .foregroundStyle(Color.erstText)
                .erstArrival(0)
            Text(OnboardingStep.welcome.detail())
                .erstStyle(Typography.lead)
                .foregroundStyle(Color.erstSecondary)
                .multilineTextAlignment(.center)
                .frame(width: OnboardingLayout.welcomeDetailWidth)
                .erstArrival(1)
            Button(action: onStart) {
                Text(OnboardingStep.welcome.actionTitle).erstStyle(Typography.headline)
            }
            .prominentAction()
            .controlSize(.extraLarge)
            .padding(.top, Spacing.xxLarge)
            .erstArrival(2, blurs: false)
        }
    }
}

@MainActor
private final class WelcomeCopyModel: ObservableObject {
    /// The copy waits for the mark to come into focus and the first echoes to leave.
    private static let copyDelaySeconds = 0.55
    @Published private(set) var showsCopy = false

    func reveal() async {
        if Motion.heldArrival == nil {
            try? await Task.sleep(for: .seconds(Self.copyDelaySeconds))
        }
        showsCopy = true
    }
}
