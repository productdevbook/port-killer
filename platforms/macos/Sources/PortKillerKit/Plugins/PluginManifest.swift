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
        public var confirmation: String?
        public var inputs: [PluginInput]?

        public init(
            id: String,
            title: String,
            icon: String? = nil,
            processes: [String]? = nil,
            ports: [Int]? = nil,
            confirmation: String? = nil,
            inputs: [PluginInput]? = nil
        ) {
            self.id = id
            self.title = title
            self.icon = icon
            self.processes = processes
            self.ports = ports
            self.confirmation = confirmation
            self.inputs = inputs
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
    public var settings: [PluginInput]?

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
        case settings
    }

    var problem: String? {
        guard id.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9._-]*/) != nil else {
            return "id may only contain letters, digits, dots, dashes and underscores."
        }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "name is empty." }
        if let problem = (settings ?? []).definitionProblem(in: "settings") { return problem }
        var actionIDs: Set<String> = []
        for action in portActions ?? [] {
            guard !action.id.isEmpty, actionIDs.insert(action.id).inserted else {
                return "portActions has an empty or repeated id."
            }
            if let problem = (action.inputs ?? []).definitionProblem(in: "Port action \(action.id)") { return problem }
        }
        return nil
    }
}
