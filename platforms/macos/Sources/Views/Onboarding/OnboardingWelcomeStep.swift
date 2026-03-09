import SwiftUI

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "network")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)

            Text("Welcome to PortKiller")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Find and kill processes on any port.\nManage your development servers with ease.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()
        }
        .padding(32)
    }
}
