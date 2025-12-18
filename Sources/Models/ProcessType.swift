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

    /// Detect the process type from a process name
    ///
    /// Analyzes the process name against known patterns to categorize it into
    /// one of the predefined process types. The detection is case-insensitive
    /// and looks for common process name patterns.
    ///
    /// - Parameter processName: The name of the process to analyze
    /// - Returns: The detected ProcessType category
    ///
    /// # Examples
    /// ```swift
    /// ProcessType.detect(from: "nginx") // .webServer
    /// ProcessType.detect(from: "postgres") // .database
    /// ProcessType.detect(from: "node") // .development
    /// ProcessType.detect(from: "launchd") // .system
    /// ProcessType.detect(from: "unknown") // .other
    /// ```
    static func detect(from processName: String) -> ProcessType {
        let name = processName.lowercased()

        // Web servers
        let webServers = ["nginx", "apache", "httpd", "caddy", "traefik", "lighttpd"]
        if webServers.contains(where: { name.contains($0) }) {
            return .webServer
        }

        // Databases
        let databases = ["postgres", "mysql", "mariadb", "redis", "mongo", "sqlite", "cockroach", "clickhouse"]
        if databases.contains(where: { name.contains($0) }) {
            return .database
        }

        // Development tools
        let devTools = ["node", "npm", "yarn", "python", "ruby", "php", "java", "go", "cargo", "swift", "vite", "webpack", "esbuild", "next", "nuxt", "remix"]
        if devTools.contains(where: { name.contains($0) }) {
            return .development
        }

        // System processes
        let systemProcs = ["launchd", "rapportd", "sharingd", "airplay", "control", "kernel", "mds", "spotlight"]
        if systemProcs.contains(where: { name.contains($0) }) {
            return .system
        }

        return .other
    }
}
