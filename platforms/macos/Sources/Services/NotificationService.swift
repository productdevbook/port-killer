/**
 * NotificationService.swift
 * PortKiller
 *
 * Manages system notifications for watched port events.
 * Handles notification center setup, permissions, and message delivery.
 */

import Foundation
import SwiftUI
@preconcurrency import UserNotifications

/// Service for managing system notifications
///
/// NotificationService centralizes all notification-related functionality,
/// including permission requests, notification delivery, and delegate handling.
/// It ensures notifications only run when the app is built as a .app bundle.
@MainActor
final class NotificationService: NSObject {
    /// Singleton instance
    static let shared = NotificationService()

    /// Notification center instance (nil if not running as .app bundle)
    private var notificationCenter: UNUserNotificationCenter? {
        // UNUserNotificationCenter only works in .app bundle
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        return UNUserNotificationCenter.current()
    }

    private override init() {
        super.init()
    }

    /// Set up the notification service and request initial permissions
    ///
    /// Call this once during app initialization. It configures the notification
    /// center delegate and requests authorization if not already determined.
    func setup() {
        guard let center = notificationCenter else { return }
        center.delegate = self

        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        }
    }

    /// Request notification permissions from the user
    ///
    /// Presents the system permission dialog if not already determined.
    ///
    /// - Returns: True if permission was granted, false otherwise
    func requestPermission() async -> Bool {
        guard let center = notificationCenter else { return false }

        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Check current notification authorization status
    ///
    /// - Returns: The current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        guard let center = notificationCenter else { return .notDetermined }
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    /// Send a notification
    ///
    /// Delivers a notification with the specified title and body.
    /// Notifications are only sent if the app is built as a .app bundle
    /// and has proper permissions.
    ///
    /// - Parameters:
    ///   - title: Notification title
    ///   - body: Notification body message
    ///
    /// # Example
    /// ```swift
    /// NotificationService.shared.notify(
    ///     title: "Port 3000 Available",
    ///     body: "Port is now free."
    /// )
    /// ```
    func notify(title: String, body: String) {
        guard let center = notificationCenter else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Handle notifications while app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
