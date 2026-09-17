public import Foundation
import OrderedCollections

public struct GraphPoint: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct GraphNode: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case process(pid: Int32)
        case forward(UUID)
        case pluginItem(plugin: String, item: String)
        case port(Int)
        case favorites
        case watch
        case share
        case quickTunnel(UUID)
        case namedTunnel(String)
        case autoKill(UUID)
        case pluginNode(UUID)
        case pluginTarget(plugin: String, item: String)
    }

    public enum Column: Int, Hashable, Sendable, CaseIterable {
        case providers
        case ports
        case consumers
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var subtitle: String
    public var symbol: String
    public var detail: String
    public var isActive: Bool

    public init(id: String, kind: Kind, title: String, subtitle: String, symbol: String, detail: String = "", isActive: Bool = true) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.detail = detail
        self.isActive = isActive
    }

    public var column: Column {
        switch kind {
        case .process, .forward, .pluginItem: .providers
        case .port: .ports
        case .favorites, .watch, .share, .quickTunnel, .namedTunnel, .autoKill, .pluginNode, .pluginTarget: .consumers
        }
    }

    public var port: Int? {
        if case .port(let port) = kind { port } else { nil }
    }

    public var acceptsLinks: Bool {
        switch kind {
        case .favorites, .watch, .share, .pluginNode: true
        default: false
        }
    }
}

public struct GraphEdge: Identifiable, Hashable, Sendable {
    public enum Origin: Hashable, Sendable {
        case system
        case link
    }

    public var from: String
    public var to: String
    public var origin: Origin

    public init(from: String, to: String, origin: Origin) {
        self.from = from
        self.to = to
        self.origin = origin
    }

    public var id: String { "\(from)→\(to)" }
}

public enum GraphChange: Hashable, Sendable {
    case favorite(Int)
    case unfavorite(Int)
    case watch(Int)
    case unwatch(Int)
    case share(Int)
    case stopSharing(UUID)
    case connectPluginNode(UUID, port: Int)
    case disconnectPluginNode(UUID, port: Int)
}

public struct PortGraph: Hashable, Sendable {
    public struct Provider: Hashable, Sendable {
        public var node: GraphNode
        public var ports: [Int]

        public init(node: GraphNode, ports: [Int]) {
            self.node = node
            self.ports = ports
        }
    }

    public struct Consumer: Hashable, Sendable {
        public var node: GraphNode
        public var ports: [Int]
        public var origin: GraphEdge.Origin

        public init(node: GraphNode, ports: [Int], origin: GraphEdge.Origin) {
            self.node = node
            self.ports = ports
            self.origin = origin
        }
    }

    public var nodes: [GraphNode]
    public var edges: [GraphEdge]

    public init(providers: [Provider], consumers: [Consumer], idlePorts: Set<Int> = []) {
        let listening = Set(providers.flatMap(\.ports))
        let firstPort: ([Int]) -> Int = { $0.min() ?? .max }
        let providers = providers.sorted { firstPort($0.ports) < firstPort($1.ports) }
        var ports = OrderedSet(providers.flatMap { $0.ports.sorted() })
        ports.append(contentsOf: idlePorts.union(consumers.flatMap(\.ports)).sorted())
        nodes = providers.map(\.node)
            + ports.map { port in
                GraphNode(
                    id: Self.portID(port),
                    kind: .port(port),
                    title: String(port),
                    subtitle: listening.contains(port) ? "Listening" : "Not Running",
                    symbol: "number",
                    isActive: listening.contains(port)
                )
            }
            + consumers.map(\.node)
        edges = providers.flatMap { provider in
            Set(provider.ports).sorted().map { GraphEdge(from: provider.node.id, to: Self.portID($0), origin: .system) }
        } + consumers.flatMap { consumer in
            Set(consumer.ports).sorted().map { GraphEdge(from: Self.portID($0), to: consumer.node.id, origin: consumer.origin) }
        }
    }

    init(nodes: [GraphNode], edges: [GraphEdge]) {
        self.nodes = nodes
        self.edges = edges
    }

    public func focused(on id: String) -> PortGraph {
        guard let center = node(id: id) else { return PortGraph(nodes: [], edges: []) }
        let ports: Set<String> = switch center.column {
        case .providers: Set(edges.filter { $0.from == id }.map(\.to))
        case .ports: [id]
        case .consumers: Set(edges.filter { $0.to == id }.map(\.from))
        }
        let kept = edges.filter { ports.contains($0.from) || ports.contains($0.to) }
        let ids = ports.union(kept.flatMap { [$0.from, $0.to] }).union([id])
        return PortGraph(nodes: nodes.filter { ids.contains($0.id) || $0.acceptsLinks }, edges: kept)
    }

    public func removing(_ shouldRemove: (GraphNode) -> Bool) -> PortGraph {
        let kept = nodes.filter { !shouldRemove($0) }
        let ids = Set(kept.map(\.id))
        return PortGraph(nodes: kept, edges: edges.filter { ids.contains($0.from) && ids.contains($0.to) })
    }

    public static func portID(_ port: Int) -> String {
        "port:\(port)"
    }

    public func node(id: String) -> GraphNode? {
        nodes.first { $0.id == id }
    }

    public func change(linking port: Int, to target: GraphNode) -> GraphChange? {
        guard !edges.contains(GraphEdge(from: Self.portID(port), to: target.id, origin: .link)) else { return nil }
        switch target.kind {
        case .favorites: return .favorite(port)
        case .watch: return .watch(port)
        case .share: return .share(port)
        case .pluginNode(let id): return .connectPluginNode(id, port: port)
        default: return nil
        }
    }

    public func change(unlinking edge: GraphEdge) -> GraphChange? {
        guard edge.origin == .link, let port = node(id: edge.from)?.port, let target = node(id: edge.to) else { return nil }
        switch target.kind {
        case .favorites: return .unfavorite(port)
        case .watch: return .unwatch(port)
        case .quickTunnel(let id): return .stopSharing(id)
        case .pluginNode(let id): return .disconnectPluginNode(id, port: port)
        default: return nil
        }
    }

    public func pins(of id: String) -> [GraphNode] {
        let ports = Set(edges.filter { $0.from == id && $0.origin == .system }.map(\.to))
        return nodes.filter { $0.column == .ports && ports.contains($0.id) }
    }

    public var blocks: [GraphNode] {
        let providers = Set(nodes.filter { $0.column == .providers }.map(\.id))
        let owned = Set(edges.filter { providers.contains($0.from) }.map(\.to))
        return nodes.filter { $0.column != .ports || !owned.contains($0.id) }
    }

    public func owner(of portID: String) -> String? {
        let providers = Set(nodes.filter { $0.column == .providers }.map(\.id))
        return edges.first { $0.to == portID && providers.contains($0.from) }?.from
    }

    public func layout(offsets: [String: GraphPoint], columnSpacing: Double, gap: Double, height: (GraphNode) -> Double) -> [String: GraphPoint] {
        var positions: [String: GraphPoint] = [:]
        var bottoms = [0.0, 0.0]
        for node in blocks {
            let column = node.column == .consumers ? 1 : 0
            let offset = offsets[node.id] ?? GraphPoint(x: 0, y: 0)
            positions[node.id] = GraphPoint(x: Double(column) * columnSpacing + offset.x, y: bottoms[column] + offset.y)
            bottoms[column] += height(node) + gap
        }
        return positions
    }
}
