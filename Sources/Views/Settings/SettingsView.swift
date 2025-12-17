/// SettingsView - Main settings interface
///
/// Displays app settings organized into sections:
/// - General preferences (launch at login)
/// - Keyboard shortcuts (global hotkeys)
/// - Permissions (accessibility, notifications)
/// - Software updates (Sparkle integration)
/// - Sponsors configuration
/// - About information
///
/// - Note: Automatically checks permissions every 5 seconds while visible.
/// - Important: Uses `@Bindable var state: AppState` for state management.

import SwiftUI
import ApplicationServices
@preconcurrency import UserNotifications
import Sparkle
import LaunchAtLogin
import Defaults

struct SettingsView: View {
    @Bindable var state: AppState
    var updateManager: UpdateManager
    @Environment(SponsorManager.self) var sponsorManager
    @Environment(\.openWindow) private var openWindow
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var permissionCheckTimer: Timer?
    @State private var sponsorDisplayInterval = Defaults[.sponsorDisplayInterval]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // MARK: - General
                GeneralSettingsSection()

                // MARK: - Keyboard Shortcuts
                ShortcutsSection()

                // MARK: - Permissions
                PermissionsSection(
                    hasAccessibility: $hasAccessibility,
                    notificationStatus: $notificationStatus,
                    onRequestNotification: requestNotificationPermission,
                    onOpenNotificationSettings: openNotificationSettings
                )

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

                // MARK: - Sponsors
                SettingsGroup("Sponsors", icon: "heart.fill") {
                    VStack(spacing: 0) {
                        SettingsRowContainer {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Show Sponsors Window")
                                        .fontWeight(.medium)
                                    Text("How often to display the sponsors window")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Picker("", selection: $sponsorDisplayInterval) {
                                    ForEach(SponsorDisplayInterval.allCases, id: \.self) { interval in
                                        Text(interval.localizedName).tag(interval)
                                    }
                                }
                                .frame(width: 130)
                                .onChange(of: sponsorDisplayInterval) { _, newValue in
                                    Defaults[.sponsorDisplayInterval] = newValue
                                }
                            }
                        }

                        SettingsDivider()

                        SettingsRowContainer {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("View Sponsors")
                                        .fontWeight(.medium)
                                    Text("See all current supporters")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Show Window") {
                                    sponsorManager.showSponsorsWindow()
                                    openWindow(id: "sponsors")
                                }
                            }
                        }
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
                        SettingsLinkRow(title: "Twitter/X", subtitle: "@productdevbook", icon: "at", url: AppInfo.twitterURL)
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

    // MARK: - Permission Management

    /// Checks current permission states
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

    /// Starts timer to periodically check permissions
    private func startPermissionTimer() {
        guard permissionCheckTimer == nil else { return }
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                self.checkPermissions()
            }
        }
    }

    /// Stops permission check timer
    private func stopPermissionTimer() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    /// Requests notification permission from user
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

    /// Opens system notification settings for this app
    private func openNotificationSettings() {
        // Open System Settings > Notifications for this app
        if let bundleId = Bundle.main.bundleIdentifier {
            let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)")!
            NSWorkspace.shared.open(url)
        }
    }
}
