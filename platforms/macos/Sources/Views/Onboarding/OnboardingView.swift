import SwiftUI
import Defaults

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch currentStep {
                case 0: OnboardingWelcomeStep()
                case 1: OnboardingFeaturesStep()
                case 2: OnboardingSetupStep()
                case 3: OnboardingReadyStep()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation
            HStack {
                // Step indicators
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentStep -= 1
                            }
                        }
                        .controlSize(.large)
                    }

                    if currentStep < totalSteps - 1 {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .controlSize(.large)
                        .foregroundStyle(.secondary)

                        Button("Next") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentStep += 1
                            }
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Get Started") {
                            completeOnboarding()
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 420)
    }

    private func completeOnboarding() {
        Defaults[.hasCompletedOnboarding] = true
        dismiss()
    }
}
