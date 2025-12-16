import SwiftUI
import ApplicationServices
@preconcurrency import UserNotifications
import Sparkle
import LaunchAtLogin

struct SettingsView: View {
    @Bindable var state: AppState
    @ObservedObject var updateManager: UpdateManager
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var permissionCheckTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // MARK: - General
                SettingsGroup("General", icon: "gearshape.fill") {
                    SettingsRowContainer {
                        LaunchAtLogin.Toggle {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Launch at Login")
                                    .fontWeight(.medium)
                                Text("Start PortKiller when you log in")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }

                // MARK: - Permissions
                SettingsGroup("Permissions", icon: "lock.shield.fill") {
                    VStack(spacing: 0) {
                        // Accessibility Permission
                        SettingsRowContainer {
                            HStack(spacing: 12) {
                                Image(systemName: hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(hasAccessibility ? .green : .orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Accessibility")
                                        .fontWeight(.medium)
                                    Text(hasAccessibility ? "Permission granted" : "Required for global shortcuts")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if hasAccessibility {
                                    Text("Granted")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.green.opacity(0.1))
                                        .clipShape(Capsule())
                                } else {
                                    Button("Grant Access") {
                                        promptAccessibility()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        }

                        SettingsDivider()

                        // Notification Permission
                        SettingsRowContainer {
                            HStack(spacing: 12) {
                                Image(systemName: notificationStatusIcon)
                                    .font(.title2)
                                    .foregroundStyle(notificationStatusColor)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Notifications")
                                        .fontWeight(.medium)
                                    Text(notificationStatusText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if notificationStatus == .authorized {
                                    Text("Enabled")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.green.opacity(0.1))
                                        .clipShape(Capsule())
                                } else if notificationStatus == .notDetermined {
                                    Button("Enable") {
                                        requestNotificationPermission()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                } else {
                                    Button("Open Settings") {
                                        openNotificationSettings()
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                // MARK: - Keyboard Shortcuts
                // FIXME: KeyboardShortcuts.Recorder crashes on macOS 26 (Tahoe) due to Bundle.module issue
                // See: https://github.com/sindresorhus/KeyboardShortcuts/issues/231
                // See: https://github.com/sindresorhus/KeyboardShortcuts/issues/229
                // Temporarily disabled until library is fixed
                /*
                SettingsGroup("Keyboard Shortcuts", icon: "keyboard.fill") {
                    SettingsRowContainer {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Toggle Main Window")
                                    .fontWeight(.medium)
                                Text("Show or hide the app window")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            KeyboardShortcuts.Recorder(for: .toggleMainWindow)
                                .frame(width: 150)
                        }
                    }
                }
                */

                // MARK: - Updates
                SettingsGroup("Software Update", icon: "arrow.triangle.2.circlepath") {
                    VStack(spacing: 0) {
                        SettingsRowContainer {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("PortKiller \(AppInfo.versionString)")
                                        .fontWeight(.medium)
                                    if let lastCheck = updateManager.lastUpdateCheckDate {
                                        Text("Last checked \(lastCheck.formatted(.relative(presentation: .named)))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Never checked for updates")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button("Check Now") {
                                    updateManager.checkForUpdates()
                                }
                                .disabled(!updateManager.canCheckForUpdates)
                            }
                        }

                        SettingsDivider()

                        SettingsToggleRow(
                            title: "Check automatically",
                            subtitle: "Look for updates in the background",
                            isOn: Binding(
                                get: { updateManager.automaticallyChecksForUpdates },
                                set: { updateManager.automaticallyChecksForUpdates = $0 }
                            )
                        )

                        SettingsDivider()

                        SettingsToggleRow(
                            title: "Download automatically",
                            subtitle: "Download updates when available",
                            isOn: Binding(
                                get: { updateManager.automaticallyDownloadsUpdates },
                                set: { updateManager.automaticallyDownloadsUpdates = $0 }
                            )
                        )
                    }
                }

                // MARK: - About
                SettingsGroup("About", icon: "info.circle.fill") {
                    VStack(spacing: 0) {
                        SettingsRowContainer {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Developer")
                                        .fontWeight(.medium)
                                    Text("productdevbook")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }

                        SettingsDivider()

                        SettingsLinkRow(title: "GitHub", subtitle: "Star the project", icon: "star.fill", url: AppInfo.githubRepo)
                        SettingsDivider()
                        SettingsLinkRow(title: "Sponsor", subtitle: "Support development", icon: "heart.fill", url: AppInfo.githubSponsors)
                        SettingsDivider()
                        SettingsLinkRow(title: "Report Issue", subtitle: "Found a bug?", icon: "ladybug.fill", url: AppInfo.githubIssues)
                        SettingsDivider()
                        SettingsLinkRow(title: "Twitter/X", subtitle: "@pdevbook", icon: "at", url: AppInfo.twitterURL)
                    }
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            checkPermissions()
            startPermissionTimer()
        }
        .onDisappear {
            stopPermissionTimer()
        }
    }

    // MARK: - Permission Helpers

    private var notificationStatusIcon: String {
        switch notificationStatus {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .provisional, .ephemeral: return "checkmark.circle.fill"
        @unknown default: return "questionmark.circle.fill"
        }
    }

    private var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        @unknown default: return .secondary
        }
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized: return "Alerts enabled for port watch"
        case .denied: return "Notifications disabled in System Settings"
        case .notDetermined: return "Required for port watch alerts"
        case .provisional: return "Provisional notifications enabled"
        case .ephemeral: return "Temporary notifications enabled"
        @unknown default: return "Unknown status"
        }
    }

    private func checkPermissions() {
        // Check accessibility
        hasAccessibility = AXIsProcessTrusted()

        // Check notification permission (only works in .app bundle)
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else {
            // Running from debug build, skip notification check
            notificationStatus = .notDetermined
            return
        }

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationStatus = settings.authorizationStatus
            }
        }
    }

    private func startPermissionTimer() {
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [self] _ in
            Task { @MainActor in
                checkPermissions()
            }
        }
    }

    private func stopPermissionTimer() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }

        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await MainActor.run {
                    checkPermissions()
                }
            } catch {
                // Permission denied or error
            }
        }
    }

    private func openNotificationSettings() {
        // Open System Settings > Notifications for this app
        if let bundleId = Bundle.main.bundleIdentifier {
            let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)")!
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Accessibility Prompt

private func promptAccessibility() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}

// MARK: - Settings Components

struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
            }

            content
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct SettingsRowContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRowContainer {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }
}

struct SettingsButtonRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowContainer {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .fontWeight(.medium)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct SettingsLinkRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            SettingsRowContainer {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .fontWeight(.medium)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 50)
    }
}
