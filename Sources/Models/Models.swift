import Foundation
import Defaults

struct PortInfo: Identifiable, Hashable, Sendable {
    let id = UUID()
    let port: Int
    let pid: Int
    let processName: String
    let address: String
    let user: String
    let command: String
    let fd: String
    let isActive: Bool

    var displayPort: String { ":\(port)" }

    var processType: ProcessType {
        ProcessType.detect(from: processName)
    }

    /// Create an inactive placeholder for a favorited/watched port
    static func inactive(port: Int) -> PortInfo {
        PortInfo(
            port: port,
            pid: 0,
            processName: "Not running",
            address: "-",
            user: "-",
            command: "",
            fd: "",
            isActive: false
        )
    }

    /// Create an active port from scan results
    static func active(port: Int, pid: Int, processName: String, address: String, user: String, command: String, fd: String) -> PortInfo {
        PortInfo(
            port: port,
            pid: pid,
            processName: processName,
            address: address,
            user: user,
            command: command,
            fd: fd,
            isActive: true
        )
    }
}

enum ProcessType: String, CaseIterable, Identifiable, Sendable {
    case webServer = "Web Server"
    case database = "Database"
    case development = "Development"
    case system = "System"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .webServer: return "globe"
        case .database: return "cylinder"
        case .development: return "hammer"
        case .system: return "gearshape"
        case .other: return "powerplug"
        }
    }

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

struct WatchedPort: Identifiable, Codable, Defaults.Serializable {
    let id: UUID
    let port: Int
    var notifyOnStart: Bool
    var notifyOnStop: Bool

    init(port: Int, notifyOnStart: Bool = true, notifyOnStop: Bool = true) {
        self.id = UUID()
        self.port = port
        self.notifyOnStart = notifyOnStart
        self.notifyOnStop = notifyOnStop
    }
}

struct ProcessGroup: Identifiable {
    let id: Int // Use PID as stable identifier
    let processName: String
    let ports: [PortInfo]
}
