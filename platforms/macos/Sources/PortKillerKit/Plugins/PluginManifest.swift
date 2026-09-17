public import Foundation

public struct PluginManifest: Codable, Sendable, Hashable {
    public struct Items: Codable, Sendable, Hashable {
        public var title: String
        public var refreshInterval: Int?

        public init(title: String, refreshInterval: Int? = nil) {
            self.title = title
            self.refreshInterval = refreshInterval
        }
    }

    public struct PortAction: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var icon: String?
        public var processes: [String]?
        public var ports: [Int]?

        public init(id: String, title: String, icon: String? = nil, processes: [String]? = nil, ports: [Int]? = nil) {
            self.id = id
            self.title = title
            self.icon = icon
            self.processes = processes
            self.ports = ports
        }

        public func applies(toPort port: Int, processName: String) -> Bool {
            if let ports, !ports.isEmpty, !ports.contains(port) { return false }
            guard let processes, !processes.isEmpty else { return true }
            return processes.contains { AutoKillRule.glob($0.lowercased(), matches: processName.lowercased()) }
        }
    }

    public var apiVersion: Int
    public var id: String
    public var name: String
    public var version: String
    public var summary: String?
    public var author: String?
    public var homepage: URL?
    public var icon: String?
    public var executable: String
    public var items: Items?
    public var portActions: [PortAction]?

    enum CodingKeys: String, CodingKey {
        case apiVersion
        case id
        case name
        case version
        case summary = "description"
        case author
        case homepage
        case icon
        case executable
        case items
        case portActions
    }
}
