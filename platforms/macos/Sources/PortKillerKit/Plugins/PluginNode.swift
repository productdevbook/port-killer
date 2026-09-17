public import Foundation

public struct PluginNode: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var pluginID: String
    public var actionID: String
    public var name: String
    public var inputs: [String: String]
    public var ports: [Int]
    public var runsWhenPortStarts: Bool

    public init(
        id: UUID = UUID(),
        pluginID: String,
        actionID: String,
        name: String,
        inputs: [String: String] = [:],
        ports: [Int] = [],
        runsWhenPortStarts: Bool = false
    ) {
        self.id = id
        self.pluginID = pluginID
        self.actionID = actionID
        self.name = name
        self.inputs = inputs
        self.ports = ports
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

public struct PluginNodes: Codable, Sendable, Hashable {
    public private(set) var all: [PluginNode]

    public init(_ all: [PluginNode] = []) {
        self.all = all
    }

    public mutating func save(_ node: PluginNode) {
        var node = node
        node.ports = Array(Set(node.ports)).sorted()
        if let index = all.firstIndex(where: { $0.id == node.id }) {
            all[index] = node
        } else {
            all.append(node)
        }
    }

    public mutating func remove(_ id: PluginNode.ID) {
        all.removeAll { $0.id == id }
    }

    public mutating func removeAll(plugin: String) {
        all.removeAll { $0.pluginID == plugin }
    }

    public mutating func connect(_ id: PluginNode.ID, to port: Int) {
        guard var node = node(id), !node.ports.contains(port) else { return }
        node.ports.append(port)
        save(node)
    }

    public mutating func disconnect(_ id: PluginNode.ID, from port: Int) {
        guard var node = node(id) else { return }
        node.ports.removeAll { $0 == port }
        save(node)
    }

    public func node(_ id: PluginNode.ID) -> PluginNode? {
        all.first { $0.id == id }
    }

    public func nodes(port: Int) -> [PluginNode] {
        all.filter { $0.ports.contains(port) }
    }

    public func duplicate(_ id: PluginNode.ID, named name: String) -> PluginNode? {
        guard var copy = node(id) else { return nil }
        copy.id = UUID()
        copy.name = name
        copy.ports = []
        return copy
    }

    public var watchedPorts: [WatchedPort] {
        Set(all.filter(\.runsWhenPortStarts).flatMap(\.ports)).sorted().map { WatchedPort(port: $0, notifyOnStart: true, notifyOnStop: false) }
    }

    public func triggered(by events: [WatchMonitor.Event]) -> [(node: PluginNode, port: Int)] {
        let started = events.compactMap { event -> Int? in
            if case .started(let port, _) = event { port } else { nil }
        }
        return started.flatMap { port in
            all.filter { $0.runsWhenPortStarts && $0.ports.contains(port) }.map { (node: $0, port: port) }
        }
    }
}
