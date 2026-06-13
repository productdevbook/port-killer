import SwiftUI

struct DependencyWarningBanner: View {
    @State private var isInstalling = false

    var body: some View {
        AlertBanner(
            icon: "exclamationmark.triangle.fill",
            title: "Missing Dependencies",
            message: "kubectl is required for port forwarding"
        ) {
            if isInstalling {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("Install") {
                    installDependencies()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func installDependencies() {
        isInstalling = true
        Task {
            _ = await DependencyChecker.shared.checkAndInstallMissing()
            await MainActor.run { isInstalling = false }
        }
    }
}
