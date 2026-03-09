import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts
@preconcurrency import UserNotifications

struct OnboardingSetupStep: View {
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Quick Setup")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 4)

            // Launch at Login
            VStack(alignment: .leading, spacing: 8) {
                LaunchAtLogin.Toggle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .fontWeight(.medium)
                        Text("Start PortKiller when you log in")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Notifications
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications")
                            .fontWeight(.medium)
                        Text("Get notified when watched ports change state")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if notificationStatus == .authorized {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Enabled")
                                .font(.callout)
                                .foregroundStyle(.green)
                        }
                    } else if notificationStatus == .denied {
                        Button("Open Settings") {
                            if let bundleId = Bundle.main.bundleIdentifier {
                                let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)")!
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    } else {
                        Button("Enable") {
                            requestPermission()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Keyboard Shortcut
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Global Shortcut")
                            .fontWeight(.medium)
                        Text("Open PortKiller from anywhere")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    KeyboardShortcuts.Recorder(for: .toggleMainWindow)
                        .frame(width: 150)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
        .padding(32)
        .task {
            await checkNotificationStatus()
        }
    }

    private func requestPermission() {
        Task {
            _ = await NotificationService.shared.requestPermission()
            await checkNotificationStatus()
        }
    }

    private func checkNotificationStatus() async {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }
}
