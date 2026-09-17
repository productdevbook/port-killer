public import Foundation

public struct PluginConnection: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var pluginID: String
    public var actionID: String
    public var port: Int
    public var inputs: [String: String]
    public var runsWhenPortStarts: Bool

    public init(id: UUID = UUID(), pluginID: String, actionID: String, port: Int, inputs: [String: String] = [:], runsWhenPortStarts: Bool = false) {
        self.id = id
        self.pluginID = pluginID
        self.actionID = actionID
        self.port = port
        self.inputs = inputs
        self.runsWhenPortStarts = runsWhenPortStarts
    }

    public func summary(using definitions: [PluginInput]) -> String? {
        let parts = definitions
            .filter { [.text, .number, .choice].contains($0.kind) }
            .compactMap { input -> String? in
                let value = (inputs[input.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        return parts.isEmpty ? nil : parts.prefix(3).joined(separator: " ")
    }
}

public struct PluginConnections: Codable, Sendable, Hashable {
    public private(set) var all: [PluginConnection]

    public init(_ all: [PluginConnection] = []) {
        self.all = all
    }

    public mutating func save(_ connection: PluginConnection) {
        if let index = all.firstIndex(where: { $0.id == connection.id }) {
            all[index] = connection
        } else {
            all.append(connection)
        }
    }

    public mutating func remove(_ id: PluginConnection.ID) {
        all.removeAll { $0.id == id }
    }

    public mutating func removeAll(plugin: String, action: String? = nil, port: Int? = nil) {
        all.removeAll { $0.pluginID == plugin && (action == nil || $0.actionID == action) && (port == nil || $0.port == port) }
    }

    public func connection(_ id: PluginConnection.ID) -> PluginConnection? {
        all.first { $0.id == id }
    }

    public func connections(plugin: String? = nil, action: String? = nil, port: Int? = nil) -> [PluginConnection] {
        all.filter { (plugin == nil || $0.pluginID == plugin) && (action == nil || $0.actionID == action) && (port == nil || $0.port == port) }
    }

    public func ports(plugin: String, action: String) -> [Int] {
        Array(Set(connections(plugin: plugin, action: action).map(\.port))).sorted()
    }

    public var watchedPorts: [WatchedPort] {
        Set(all.filter(\.runsWhenPortStarts).map(\.port)).sorted().map { WatchedPort(port: $0, notifyOnStart: true, notifyOnStop: false) }
    }

    public func triggered(by events: [WatchMonitor.Event]) -> [PluginConnection] {
        let started = Set(events.compactMap { event -> Int? in
            if case .started(let port, _) = event { port } else { nil }
        })
        return all.filter { $0.runsWhenPortStarts && started.contains($0.port) }
    }
}
