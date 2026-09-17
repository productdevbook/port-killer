import Foundation
import Testing
@testable import PortKillerKit

struct PluginConnectionTests {
    let request = [
        PluginInput(id: "method", label: "Method", type: .choice, options: ["GET", "POST"]),
        PluginInput(id: "path", label: "Path"),
        PluginInput(id: "body", label: "Body", type: .multiline),
        PluginInput(id: "token", label: "Token", type: .secret),
    ]

    @Test func summarizesShortInputs() {
        let connection = PluginConnection(pluginID: "http", actionID: "send", port: 3000, inputs: ["method": "POST", "path": " /users ", "body": "{}", "token": "abc"])
        #expect(connection.summary(using: request) == "POST /users")
        #expect(PluginConnection(pluginID: "http", actionID: "get", port: 3000).summary(using: request) == nil)
    }

    @Test func savesUpdatesAndRemovesConnections() {
        var connections = PluginConnections()
        let health = PluginConnection(pluginID: "http", actionID: "send", port: 3000, inputs: ["path": "/health"])
        let users = PluginConnection(pluginID: "http", actionID: "send", port: 3000, inputs: ["path": "/users"])
        let other = PluginConnection(pluginID: "http", actionID: "get", port: 5173)
        let editor = PluginConnection(pluginID: "editor", actionID: "code", port: 3000)
        for connection in [health, users, other, editor] {
            connections.save(connection)
        }

        #expect(connections.connections(port: 3000).map(\.id) == [health.id, users.id, editor.id])
        #expect(connections.connections(plugin: "http", action: "send", port: 3000).count == 2)
        #expect(connections.ports(plugin: "http", action: "send") == [3000])
        #expect(connections.ports(plugin: "http", action: "get") == [5173])

        var edited = health
        edited.inputs["path"] = "/ready"
        connections.save(edited)
        #expect(connections.all.count == 4)
        #expect(connections.connection(health.id)?.inputs["path"] == "/ready")

        connections.remove(users.id)
        #expect(connections.connection(users.id) == nil)
        connections.removeAll(plugin: "http", action: "send", port: 3000)
        #expect(connections.connections(plugin: "http", action: "send").isEmpty)
        connections.removeAll(plugin: "http")
        #expect(connections.all.map(\.id) == [editor.id])
    }

    @Test func runsConnectionsWhenTheirPortStarts() {
        let onStart = PluginConnection(pluginID: "http", actionID: "send", port: 3000, runsWhenPortStarts: true)
        let manual = PluginConnection(pluginID: "http", actionID: "get", port: 3000)
        let elsewhere = PluginConnection(pluginID: "editor", actionID: "code", port: 5173, runsWhenPortStarts: true)
        let connections = PluginConnections([onStart, manual, elsewhere])
        #expect(connections.watchedPorts.map(\.port) == [3000, 5173])
        #expect(connections.watchedPorts.allSatisfy { $0.notifyOnStart && !$0.notifyOnStop })

        var monitor = WatchMonitor()
        let node = ListeningPort(port: 3000, addresses: ["127.0.0.1"], process: ProcessSnapshot(pid: 7, name: "node"))
        #expect(connections.triggered(by: monitor.events(watched: connections.watchedPorts, ports: [])).isEmpty)
        #expect(connections.triggered(by: monitor.events(watched: connections.watchedPorts, ports: [node])).map(\.id) == [onStart.id])
        #expect(connections.triggered(by: monitor.events(watched: connections.watchedPorts, ports: [node])).isEmpty)
        #expect(connections.triggered(by: monitor.events(watched: connections.watchedPorts, ports: [])).isEmpty)
    }

    @Test func findsTheLatestRunOfAConnection() {
        var activity = PluginActivity()
        let connection = UUID()
        activity.start(PluginRun(pluginID: "http", actionID: "send", connectionID: connection, title: "HTTP Request…", target: .port(3000)))
        let latest = activity.start(PluginRun(pluginID: "http", actionID: "send", connectionID: connection, title: "HTTP Request…", target: .port(3000)))
        activity.start(PluginRun(pluginID: "http", actionID: "send", title: "HTTP Request…", target: .port(3000)))
        #expect(activity.latest(connection: connection)?.id == latest)
        #expect(activity.latest(connection: UUID()) == nil)
    }
}
