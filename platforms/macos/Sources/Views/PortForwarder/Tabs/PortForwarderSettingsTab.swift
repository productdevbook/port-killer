import SwiftUI

struct PortForwarderSettingsTab: View {
    @AppStorage("portForwardAutoStart") private var autoStart = false
    @AppStorage("portForwardShowNotifications") private var showNotifications = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Auto-start connections on app launch", isOn: $autoStart)
            }

            Section("Notifications") {
                Toggle("Show connection notifications", isOn: $showNotifications)
            }

            Section("Dependencies") {
                DependencyRow(
                    name: "kubectl",
                    dependency: DependencyChecker.shared.kubectl,
                    currentPath: DependencyChecker.shared.kubectlPath,
                    isCustom: DependencyChecker.shared.isUsingCustomKubectl,
                    customPathKey: .customKubectlPath
                )

                DependencyRow(
                    name: "socat",
                    dependency: DependencyChecker.shared.socat,
                    currentPath: DependencyChecker.shared.socatPath,
                    isCustom: DependencyChecker.shared.isUsingCustomSocat,
                    customPathKey: .customSocatPath
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
