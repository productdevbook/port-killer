import SwiftUI

struct PortForwarderSettingsTab: View {
    @Environment(AppState.self) private var appState

    @State private var autoStart = true
    @State private var showNotifications = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Auto-start connections on app launch", isOn: Binding(
                    get: { autoStart },
                    set: { newValue in
                        autoStart = newValue
                        appState.scanner.setSettingsPortForwardAutoStart(newValue)
                    }
                ))
            }

            Section("Notifications") {
                Toggle("Show connection notifications", isOn: Binding(
                    get: { showNotifications },
                    set: { newValue in
                        showNotifications = newValue
                        appState.scanner.setSettingsPortForwardShowNotifications(newValue)
                    }
                ))
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
        .onAppear {
            // Load settings from Rust config
            autoStart = appState.scanner.getSettingsPortForwardAutoStart()
            showNotifications = appState.scanner.getSettingsPortForwardShowNotifications()
        }
    }
}
