import ErstModel
import SwiftUI

/// First launch: the welcome, then one step at a time, each with its title, what to do, and a
/// footer whose small e heats up as the steps are done.
public struct OnboardingScreen: View {
    private let step: OnboardingStep
    private let state: OnboardingState
    private let actions: OnboardingActions
    private let shortcuts: ShortcutsModel

    public init(
        step: OnboardingStep = .welcome, state: OnboardingState, actions: OnboardingActions = .init(),
        shortcuts: ShortcutsModel = ShortcutsModel()
    ) {
        self.step = step
        self.state = state
        self.actions = actions
        self.shortcuts = shortcuts
    }

    public var body: some View {
        Group {
            if step == .welcome {
                OnboardingWelcome(onStart: actions.proceed)
            } else {
                page
            }
        }
        .frame(width: OnboardingLayout.windowWidth)
        .frame(maxHeight: .infinity)
        .background(Color.erstGround)
        .preferredColorScheme(.dark)
        .task {
            Typography.registerFonts()
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(step.title)
                .erstStyle(Typography.stepTitle)
                .foregroundStyle(Color.erstText)
                .padding(.bottom, Spacing.small)
                .erstArrival(0)
            Text(step.detail(shortcuts: shortcuts.shortcuts))
                .erstStyle(Typography.lead)
                .foregroundStyle(Color.erstSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: OnboardingLayout.detailWidth, alignment: .leading)
                .erstArrival(1)
            Spacer(minLength: Spacing.xxxLarge)
            OnboardingStepContent(step: step, state: state, actions: actions, shortcuts: shortcuts)
                .erstArrival(2, blurs: false)
            Spacer(minLength: Spacing.xxxLarge)
            footer
                .erstArrival(3, blurs: false)
        }
        .padding(.top, OnboardingLayout.titleTop)
        .padding(.horizontal, OnboardingLayout.sideInset)
        .padding(.bottom, OnboardingLayout.bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .erstArrivalStage(replay: step)
    }

    private var footer: some View {
        HStack(spacing: Spacing.medium) {
            ProgressMark(heated: step.heatedParts, side: OnboardingLayout.progressMarkSide)
            Text(step.progressTitle)
                .erstStyle(Typography.body)
                .foregroundStyle(Color.erstSecondary)
            Spacer(minLength: 0)
            if step.isSkippable && !state.allowsContinue(on: step) {
                Button(action: actions.skip) {
                    Text("Skip").erstStyle(Typography.bodyMedium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.erstSecondary)
                .padding(.trailing, Spacing.small)
            }
            Button(action: actions.proceed) {
                Text(step.actionTitle).erstStyle(Typography.headline)
            }
            .prominentAction()
            .controlSize(.extraLarge)
            .disabled(!state.allowsContinue(on: step))
        }
    }
}
