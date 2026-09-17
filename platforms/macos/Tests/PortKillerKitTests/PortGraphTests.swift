import Foundation
import Testing
@testable import PortKillerKit

struct PortGraphTests {
    let tunnelID = UUID()

    var graph: PortGraph {
        PortGraph(
            providers: [
                .init(node: GraphNode(id: "process:vite", kind: .process(pid: 20), title: "vite", subtitle: "", symbol: "hammer"), ports: [5173]),
                .init(node: GraphNode(id: "process:node", kind: .process(pid: 10), title: "node", subtitle: "", symbol: "hammer"), ports: [3000, 9229]),
            ],
            consumers: [
                .init(node: GraphNode(id: "favorites", kind: .favorites, title: "Favorites", subtitle: "", symbol: "star"), ports: [3000, 8080], origin: .link),
                .init(node: GraphNode(id: "watch", kind: .watch, title: "Watch", subtitle: "", symbol: "eye"), ports: [], origin: .link),
                .init(node: GraphNode(id: "share", kind: .share, title: "Quick Tunnel", subtitle: "", symbol: "bolt"), ports: [], origin: .link),
                .init(node: GraphNode(id: "quick:\(tunnelID)", kind: .quickTunnel(tunnelID), title: "abc.trycloudflare.com", subtitle: "", symbol: "bolt"), ports: [3000], origin: .link),
                .init(node: GraphNode(id: "tunnel:dev", kind: .namedTunnel("dev"), title: "dev", subtitle: "", symbol: "cloud"), ports: [5173], origin: .system),
                .init(node: GraphNode(id: "action:editor:code", kind: .pluginAction(plugin: "editor", action: "code"), title: "Open in VS Code", subtitle: "", symbol: "chevron.left.forwardslash.chevron.right"), ports: [], origin: .link),
            ],
            idlePorts: [8080]
        )
    }

    @Test func connectsProvidersPortsAndConsumers() {
        let graph = graph
        #expect(graph.nodes.filter { $0.column == .providers }.map(\.id) == ["process:node", "process:vite"])
        #expect(graph.nodes.compactMap(\.port) == [3000, 9229, 5173, 8080])
        #expect(graph.node(id: "port:8080")?.isActive == false)
        #expect(graph.node(id: "port:3000")?.subtitle == "Listening")
        #expect(graph.edges.contains(GraphEdge(from: "process:node", to: "port:9229", origin: .system)))
        #expect(graph.edges.contains(GraphEdge(from: "port:3000", to: "favorites", origin: .link)))
        #expect(graph.edges.contains(GraphEdge(from: "port:5173", to: "tunnel:dev", origin: .system)))
        #expect(graph.edges.count == 7)
    }

    @Test func focusesOnOneItemAndItsConnections() {
        let graph = graph
        let node = graph.focused(on: "process:node")
        #expect(node.nodes.map(\.id) == ["process:node", "port:3000", "port:9229", "favorites", "watch", "share", "quick:\(tunnelID)", "action:editor:code"])
        #expect(Set(node.edges.map(\.id)) == ["process:node→port:3000", "process:node→port:9229", "port:3000→favorites", "port:3000→quick:\(tunnelID)"])
        let tunnel = graph.focused(on: "tunnel:dev")
        #expect(tunnel.nodes.filter { !$0.acceptsLinks }.map(\.id) == ["process:vite", "port:5173", "tunnel:dev"])
        #expect(graph.focused(on: "port:8080").edges.map(\.id) == ["port:8080→favorites"])
        #expect(graph.focused(on: "missing").nodes.isEmpty)
    }

    @Test func linkingAPortChangesItsSettings() throws {
        let graph = graph
        #expect(graph.change(linking: 5173, to: try #require(graph.node(id: "watch"))) == .watch(5173))
        #expect(graph.change(linking: 5173, to: try #require(graph.node(id: "favorites"))) == .favorite(5173))
        #expect(graph.change(linking: 3000, to: try #require(graph.node(id: "favorites"))) == nil)
        #expect(graph.change(linking: 9229, to: try #require(graph.node(id: "share"))) == .share(9229))
        #expect(graph.change(linking: 9229, to: try #require(graph.node(id: "action:editor:code"))) == .runPluginAction(plugin: "editor", action: "code", port: 9229))
        #expect(graph.change(linking: 9229, to: try #require(graph.node(id: "tunnel:dev"))) == nil)
        #expect(graph.change(linking: 9229, to: try #require(graph.node(id: "process:vite"))) == nil)
    }

    @Test func unlinkingOnlyUndoesUserLinks() {
        let graph = graph
        #expect(graph.change(unlinking: GraphEdge(from: "port:3000", to: "favorites", origin: .link)) == .unfavorite(3000))
        #expect(graph.change(unlinking: GraphEdge(from: "port:3000", to: "quick:\(tunnelID)", origin: .link)) == .stopSharing(tunnelID))
        #expect(graph.change(unlinking: GraphEdge(from: "port:5173", to: "tunnel:dev", origin: .system)) == nil)
        #expect(graph.change(unlinking: GraphEdge(from: "process:node", to: "port:3000", origin: .system)) == nil)
    }

    @Test func laysOutColumnsAndKeepsMovedNodes() {
        let graph = graph
        let positions = graph.layout(saved: ["watch": GraphPoint(x: 900, y: -40)], columnSpacing: 300, rowSpacing: 100)
        #expect(positions.count == graph.nodes.count)
        #expect(positions["process:node"]?.x == 0)
        #expect(positions["port:3000"]?.x == 300)
        #expect(positions["favorites"]?.x == 600)
        #expect(positions["watch"] == GraphPoint(x: 900, y: -40))
        #expect(graph.nodes.filter { $0.column == .ports }.compactMap { positions[$0.id]?.y } == [0, 100, 200, 300])
        #expect(positions["process:node"]?.y == 50)
        #expect(positions["process:vite"]?.y == 200)
        #expect(positions["favorites"]?.y == -100)
    }
}
