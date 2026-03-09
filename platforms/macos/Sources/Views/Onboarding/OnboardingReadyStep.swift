import SwiftUI

struct OnboardingReadyStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("PortKiller is ready to use.\nLook for the icon in your menu bar.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            HStack(spacing: 24) {
                tipView(icon: "menubar.arrow.up.rectangle", text: "Click the menu bar icon\nfor quick access")
                tipView(icon: "gearshape.fill", text: "Visit Settings to\ncustomize further")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(32)
    }

    private func tipView(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 140)
    }
}
