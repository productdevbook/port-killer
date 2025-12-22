/**
 * ProcessType.swift
 * PortKiller
 *
 * Categorizes processes into different types based on their name and function.
 * Used to provide visual indicators and filtering capabilities in the UI.
 */

import Foundation

/// Category of process based on its function
///
/// ProcessType provides automatic detection of process categories based on
/// well-known process names, enabling better organization and visualization
/// in the UI through icons and color coding.
enum ProcessType: String, CaseIterable, Identifiable, Sendable {
    /// Web servers (nginx, apache, caddy, etc.)
    case webServer = "Web Server"

    /// Database servers (postgres, mysql, redis, etc.)
    case database = "Database"

    /// Development tools (node, python, vite, etc.)
    case development = "Development"

    /// System processes (launchd, kernel services, etc.)
    case system = "System"

    /// Other/unknown processes
    case other = "Other"

    /// Unique identifier for this process type
    var id: String { rawValue }

    /// SF Symbol icon name for this process type
    var icon: String {
        switch self {
        case .webServer: return "globe"
        case .database: return "cylinder"
        case .development: return "hammer"
        case .system: return "gearshape"
        case .other: return "powerplug"
        }
    }

    /// Convert from Rust FFI string representation.
    ///
    /// Maps the camelCase string from Rust ProcessType to Swift enum.
    /// - Parameter rustString: The string from Rust FFI ("webServer", "database", etc.)
    /// - Returns: The corresponding ProcessType, defaults to .other if unknown
    static func fromRustString(_ rustString: String) -> ProcessType {
        switch rustString {
        case "webServer": return .webServer
        case "database": return .database
        case "development": return .development
        case "system": return .system
        default: return .other
        }
    }
}
