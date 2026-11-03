/**
 * Errors.swift
 * PortKiller
 *
 * Defines error types for the PortKiller application.
 * All errors conform to LocalizedError to provide user-friendly messages.
 */

import Foundation

/// Application-specific error types
///
/// PortKillerError defines all possible error conditions that can occur
/// during port scanning, process killing, and permission checks. Each error
/// provides localized, user-friendly descriptions suitable for display in alerts.
enum PortKillerError: Error, LocalizedError {
    /// Port scanning operation failed
    case scanFailed(String)

    /// Failed to kill a process
    case killFailed(pid: Int, reason: String)

    /// Required system permission is denied
    case permissionDenied

    /// Network or system operation error
    case networkError(String)

    /// User-friendly error description
    var errorDescription: String? {
        switch self {
        case .scanFailed(let reason):
            return L10n.format("Failed to scan ports: %@", reason)
        case .killFailed(let pid, let reason):
            return L10n.format("Failed to kill process %lld: %@", pid, reason)
        case .permissionDenied:
            return L10n.tr("Permission denied. PortKiller requires accessibility permissions to manage processes.")
        case .networkError(let reason):
            return L10n.format("Network error: %@", reason)
        }
    }

    /// Detailed failure reason
    var failureReason: String? {
        switch self {
        case .scanFailed:
            return L10n.tr("The port scanning operation could not complete successfully.")
        case .killFailed:
            return L10n.tr("The process termination request was denied or failed.")
        case .permissionDenied:
            return L10n.tr("PortKiller does not have the necessary system permissions.")
        case .networkError:
            return L10n.tr("A network or system-level error occurred.")
        }
    }

    /// Suggested recovery action
    var recoverySuggestion: String? {
        switch self {
        case .scanFailed:
            return L10n.tr("Try refreshing the port list or restarting PortKiller.")
        case .killFailed:
            return L10n.format("The process may require elevated privileges. Try running 'sudo kill -9 %lld' in Terminal.", pid)
        case .permissionDenied:
            return L10n.tr("Go to System Settings > Privacy & Security > Accessibility and enable PortKiller.")
        case .networkError:
            return L10n.tr("Check your network connection and try again.")
        }
    }

    /// PID involved in the error (if applicable)
    private var pid: Int {
        switch self {
        case .killFailed(let pid, _):
            return pid
        default:
            return 0
        }
    }
}
