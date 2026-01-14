/**
 * PermissionService.swift
 * PortKiller
 *
 * Centralized service for managing system permissions.
 * Handles accessibility and notification permission checks and requests.
 */

import Foundation
import SwiftUI
import ApplicationServices
@preconcurrency import UserNotifications

/// Service for managing system permissions
///
/// PermissionService centralizes all permission-related logic, including
/// checking and requesting accessibility and notification permissions.
/// It provides reactive properties for observing permission state changes.
@MainActor
@Observable
final class PermissionService {
    /// Singleton instance
    static let shared = PermissionService()

    /// Whether accessibility permission is granted
    var hasAccessibilityPermission: Bool = false

    /// Current notification authorization status
    var notificationStatus: UNAuthorizationStatus = .notDetermined

    /// Timer for periodic permission checks
    @ObservationIgnored
    private var permissionCheckTimer: Timer?

    private init() {
        checkPermissions()
    }

    /// Whether notification permission is granted
    var hasNotificationPermission: Bool {
        notificationStatus == .authorized
    }

    // MARK: - Accessibility Permission

    /// Check if accessibility permission is granted
    ///
    /// - Returns: True if accessibility permission is granted
    func checkAccessibility() -> Bool {
        let hasPermission = AXIsProcessTrusted()
        hasAccessibilityPermission = hasPermission
        return hasPermission
    }

    /// Request accessibility permission
    ///
    /// Opens the system accessibility permission dialog.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Notification Permission

    /// Check current notification permission status
    ///
    /// - Returns: Current authorization status
    func checkNotificationPermission() async -> UNAuthorizationStatus {
        // Only check if running as .app bundle
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else {
            notificationStatus = .notDetermined
            return .notDetermined
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
        return settings.authorizationStatus
    }

    /// Request notification permission
    ///
    /// Presents the system notification permission dialog.
    ///
    /// - Returns: True if permission was granted
    func requestNotificationPermission() async -> Bool {
        guard Bundle.main.bundlePath.hasSuffix(".app") else {
            return false
        }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            _ = await checkNotificationPermission()
            return granted
        } catch {
            return false
        }
    }

    /// Open system notification settings for this app
    func openNotificationSettings() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let urlString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Periodic Checks

    /// Check all permissions
    ///
    /// Updates both accessibility and notification permission status.
    func checkPermissions() {
        // Check accessibility
        hasAccessibilityPermission = AXIsProcessTrusted()

        // Check notification permission (only works in .app bundle)
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else {
            notificationStatus = .notDetermined
            return
        }

        Task {
            await checkNotificationPermission()
        }
    }

    /// Start periodic permission checks
    ///
    /// Checks permissions every 5 seconds to detect changes made in System Settings.
    func startPeriodicChecks() {
        guard permissionCheckTimer == nil else { return }
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermissions()
            }
        }
    }

    /// Stop periodic permission checks
    func stopPeriodicChecks() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    // MARK: - UI Helpers

    /// Icon name for notification status
    var notificationStatusIcon: String {
        switch notificationStatus {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .provisional, .ephemeral: return "checkmark.circle.fill"
        @unknown default: return "questionmark.circle.fill"
        }
    }

    /// Color for notification status
    var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        @unknown default: return .secondary
        }
    }

    /// Text description for notification status
    var notificationStatusText: String {
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
