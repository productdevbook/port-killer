import Foundation
import Testing
@testable import PortKillerKit

struct PluginNodeTests {
    let request = [
        PluginInput(id: "method", label: "Method", type: .choice, options: ["GET", "POST"]),
        PluginInput(id: "path", label: "Path"),
        PluginInput(id: "body", label: "Body", type: .multiline),
        PluginInput(id: "token", label: "Token", type: .secret),
    ]

    @Test func summarizesShortInputs() {
        let node = PluginNode(pluginID: "http", actionID: "send", name: "Create User", inputs: ["method": "POST", "path": " /users ", "body": "{}", "token": "abc"])
        #expect(node.summary(using: request) == "POST /users")
        #expect(PluginNode(pluginID: "editor", actionID: "code", name: "Open").summary(using: request) == nil)
    }

    @Test func connectsNodesToPorts() {
        var nodes = PluginNodes()
        let health = PluginNode(pluginID: "http", actionID: "send", name: "Health", inputs: ["path": "/health"], ports: [5173, 3000, 3000])
        let users = PluginNode(pluginID: "http", actionID: "send", name: "Users", inputs: ["path": "/users"])
        let editor = PluginNode(pluginID: "editor", actionID: "code", name: "Editor", ports: [3000])
        for node in [health, users, editor] {
            nodes.save(node)
        }
        #expect(nodes.node(health.id)?.ports == [3000, 5173])

        nodes.connect(users.id, to: 3000)
        nodes.connect(users.id, to: 3000)
        #expect(nodes.node(users.id)?.ports == [3000])
        #expect(nodes.nodes(port: 3000).map(\.name) == ["Health", "Users", "Editor"])

        nodes.disconnect(health.id, from: 3000)
        #expect(nodes.node(health.id)?.ports == [5173])

        var renamed = users
        renamed.name = "Create User"
        renamed.ports = [3000]
        nodes.save(renamed)
        #expect(nodes.all.count == 3)
        #expect(nodes.node(users.id)?.name == "Create User")

        let copy = nodes.duplicate(health.id, named: "Health 2")
        #expect(copy?.name == "Health 2")
        #expect(copy?.inputs == health.inputs)
        #expect(copy?.ports == [])
        #expect(copy?.id != health.id)

        nodes.remove(users.id)
        #expect(nodes.node(users.id) == nil)
        nodes.removeAll(plugin: "http")
        #expect(nodes.all.map(\.id) == [editor.id])
    }

    @Test func runsNodesWhenAConnectedPortStarts() {
        let health = PluginNode(pluginID: "http", actionID: "send", name: "Health", ports: [3000, 5173], runsWhenPortStarts: true)
        let manual = PluginNode(pluginID: "http", actionID: "send", name: "Manual", ports: [3000])
        let nodes = PluginNodes([health, manual])
        #expect(nodes.watchedPorts.map(\.port) == [3000, 5173])
        #expect(nodes.watchedPorts.allSatisfy { $0.notifyOnStart && !$0.notifyOnStop })

        var monitor = WatchMonitor()
        let vite = ListeningPort(port: 5173, addresses: ["127.0.0.1"], process: ProcessSnapshot(pid: 7, name: "node"))
        #expect(nodes.triggered(by: monitor.events(watched: nodes.watchedPorts, ports: [])).isEmpty)
        let started = nodes.triggered(by: monitor.events(watched: nodes.watchedPorts, ports: [vite]))
        #expect(started.map(\.node.id) == [health.id])
        #expect(started.map(\.port) == [5173])
        #expect(nodes.triggered(by: monitor.events(watched: nodes.watchedPorts, ports: [vite])).isEmpty)
    }

    @Test func findsTheLatestRunOfANode() {
        var activity = PluginActivity()
        let node = UUID()
        activity.start(PluginRun(pluginID: "http", actionID: "send", nodeID: node, title: "Health", target: .port(3000)))
        let onVite = activity.start(PluginRun(pluginID: "http", actionID: "send", nodeID: node, title: "Health", target: .port(5173)))
        activity.start(PluginRun(pluginID: "http", actionID: "send", title: "HTTP Request…", target: .port(3000)))
        #expect(activity.latest(node: node)?.id == onVite)
        #expect(activity.latest(node: node, port: 3000)?.target == .port(3000))
        #expect(activity.isRunning(node: node))
        #expect(activity.latest(node: UUID()) == nil)
    }
}
