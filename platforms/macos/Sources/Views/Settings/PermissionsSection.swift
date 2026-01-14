/// PermissionsSection - Permission management UI
///
/// Manages accessibility and notification permissions:
/// - Shows current permission status with visual indicators
/// - Provides buttons to grant or configure permissions
/// - Displays helpful status messages
///
/// - Note: Accessibility is required for global keyboard shortcuts.
/// - Important: Notification permission only works in .app bundles.

import SwiftUI
import ApplicationServices
@preconcurrency import UserNotifications

struct PermissionsSection: View {
    @Binding var hasAccessibility: Bool
    @Binding var notificationStatus: UNAuthorizationStatus
    let onRequestNotification: () -> Void
    let onOpenNotificationSettings: () -> Void

    var body: some View {
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
                                onRequestNotification()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button("Open Settings") {
                                onOpenNotificationSettings()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Notification Status Helpers

    /// Returns appropriate icon for notification status
    private var notificationStatusIcon: String {
        switch notificationStatus {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .provisional, .ephemeral: return "checkmark.circle.fill"
        @unknown default: return "questionmark.circle.fill"
        }
    }

    /// Returns color for notification status indicator
    private var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        @unknown default: return .secondary
        }
    }

    /// Returns descriptive text for notification status
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
}

// MARK: - Accessibility Prompt

/// Prompts user to grant accessibility permission
private func promptAccessibility() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}
