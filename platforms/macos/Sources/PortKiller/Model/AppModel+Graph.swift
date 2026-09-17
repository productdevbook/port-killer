import Foundation
import PortKillerKit
import SwiftUI

struct GraphZoomRequest: Equatable {
    enum Kind: CaseIterable {
        case zoomOut
        case fit
        case actualSize
        case zoomIn

        var title: String {
            switch self {
            case .zoomOut: "Zoom Out"
            case .fit: "Zoom to Fit"
            case .actualSize: "Actual Size"
            case .zoomIn: "Zoom In"
            }
        }

        var symbol: String {
            switch self {
            case .zoomOut: "minus.magnifyingglass"
            case .fit: "arrow.up.left.and.down.right.magnifyingglass"
            case .actualSize: "1.magnifyingglass"
            case .zoomIn: "plus.magnifyingglass"
            }
        }

        var shortcut: KeyEquivalent {
            switch self {
            case .zoomOut: "-"
            case .fit: "9"
            case .actualSize: "0"
            case .zoomIn: "="
            }
        }
    }

    var kind: Kind
    var id = UUID()
}

extension AppModel {
    var portGraph: PortGraph {
        let processes = ports.processes(for: portScope)
        let duplicateNames = Dictionary(grouping: processes, by: \.process.name).filter { $0.value.count > 1 }
        var providers = processes.map { item in
            PortGraph.Provider(
                node: GraphNode(
                    id: duplicateNames[item.process.name] == nil ? "process:\(item.process.name)" : "process:\(item.process.name):\(item.process.pid)",
                    kind: .process(pid: item.process.pid),
                    title: item.process.name,
                    subtitle: [item.label ?? item.category.rawValue, "PID \(String(item.process.pid))"].joined(separator: " · "),
                    symbol: item.category.symbolName
                ),
                ports: item.ports.map(\.port)
            )
        }
        providers += forwards.sessions.map { session in
            PortGraph.Provider(
                node: GraphNode(
                    id: "forward:\(session.id)",
                    kind: .forward(session.id),
                    title: session.configuration.name,
                    subtitle: "\(session.configuration.target) · \(session.status.title)",
                    symbol: "point.3.connected.trianglepath.dotted",
                    isActive: session.isActive
                ),
                ports: [session.configuration.effectivePort]
            )
        }
        for plugin in plugins.itemPlugins {
            for item in plugins.items[plugin.id] ?? [] {
                guard let port = item.port else { continue }
                providers.append(PortGraph.Provider(
                    node: GraphNode(
                        id: "plugin:\(plugin.id):\(item.id)",
                        kind: .pluginItem(plugin: plugin.id, item: item.id),
                        title: item.title,
                        subtitle: item.subtitle ?? plugin.manifest.name,
                        symbol: plugin.manifest.icon ?? "puzzlepiece.extension",
                        isActive: item.status != .stopped
                    ),
                    ports: [port]
                ))
            }
        }

        var consumers = [
            PortGraph.Consumer(
                node: GraphNode(
                    id: "favorites",
                    kind: .favorites,
                    title: "Favorites",
                    subtitle: "PortKiller",
                    symbol: "star.fill",
                    detail: "Stars a port so the sidebar's Favorites filter shows it."
                ),
                ports: preferences.favorites.sorted(),
                origin: .link
            ),
            PortGraph.Consumer(
                node: GraphNode(
                    id: "watch",
                    kind: .watch,
                    title: "Watch",
                    subtitle: "PortKiller",
                    symbol: "eye.fill",
                    detail: "Notifies you when something starts or stops listening on a port."
                ),
                ports: preferences.watchedPorts.map(\.port),
                origin: .link
            ),
        ]
        if tunnels.isInstalled {
            consumers.append(PortGraph.Consumer(
                node: GraphNode(
                    id: "share",
                    kind: .share,
                    title: "Quick Tunnel",
                    subtitle: "cloudflared",
                    symbol: "bolt.fill",
                    detail: "Shares a port on a random trycloudflare.com address until PortKiller quits."
                ),
                ports: [],
                origin: .link
            ))
        }
        consumers += tunnels.quickTunnels.map { tunnel in
            PortGraph.Consumer(
                node: GraphNode(
                    id: "quick:\(tunnel.port)",
                    kind: .quickTunnel(tunnel.id),
                    title: tunnel.host ?? "Quick Tunnel",
                    subtitle: tunnel.status.title,
                    symbol: "bolt.fill",
                    detail: tunnel.host.map { "Shares localhost:\(String(tunnel.port)) at \($0)." } ?? "Getting a public address for localhost:\(String(tunnel.port)).",
                    isActive: tunnel.status == .active
                ),
                ports: [tunnel.port],
                origin: .link
            )
        }
        consumers += tunnels.namedTunnels.filter(\.isRunningHere).map { tunnel in
            PortGraph.Consumer(
                node: GraphNode(
                    id: "tunnel:\(tunnel.id)",
                    kind: .namedTunnel(tunnel.id),
                    title: tunnel.name,
                    subtitle: tunnel.statusTitle,
                    symbol: "cloud.fill",
                    detail: "Routes this Cloudflare Tunnel's public hostnames to local ports."
                ),
                ports: tunnel.ingressRules.compactMap(\.localPort),
                origin: .system
            )
        }
        consumers += preferences.autoKillRules.filter { $0.isEnabled && $0.isValid }.map { rule in
            PortGraph.Consumer(
                node: GraphNode(
                    id: "rule:\(rule.id)",
                    kind: .autoKill(rule.id),
                    title: rule.name.isEmpty ? "Auto-Kill" : rule.name,
                    subtitle: "Auto-Kill Rule",
                    symbol: "timer",
                    detail: "Stops a matching port's process after it listens for \(rule.timeoutMinutes) min."
                ),
                ports: ports.ports.filter { rule.matches(port: $0.port, processName: $0.processName) }.map(\.port),
                origin: .system
            )
        }
        for plugin in plugins.itemPlugins {
            for item in plugins.items[plugin.id] ?? [] {
                guard let targets = item.targetPorts, !targets.isEmpty else { continue }
                consumers.append(PortGraph.Consumer(
                    node: GraphNode(
                        id: "target:\(plugin.id):\(item.id)",
                        kind: .pluginTarget(plugin: plugin.id, item: item.id),
                        title: item.title,
                        subtitle: plugin.manifest.name,
                        symbol: plugin.manifest.icon ?? "puzzlepiece.extension",
                        detail: item.subtitle ?? "",
                        isActive: item.status != .stopped
                    ),
                    ports: targets,
                    origin: .system
                ))
            }
        }
        for node in plugins.nodes.all {
            guard let (plugin, action) = plugins.pluginAction(for: node) else { continue }
            consumers.append(PortGraph.Consumer(
                node: GraphNode(
                    id: "node:\(node.id)",
                    kind: .pluginNode(node.id),
                    title: node.name,
                    subtitle: "\(action.title.trimmingCharacters(in: ["…"])) · \(plugin.manifest.name)",
                    symbol: action.icon ?? plugin.manifest.icon ?? "puzzlepiece.extension",
                    detail: node.summary(using: action.inputs ?? []) ?? action.summary ?? ""
                ),
                ports: node.ports,
                origin: .link
            ))
        }
        return PortGraph(providers: providers, consumers: consumers, idlePorts: Set(ports.inactivePorts(for: portScope)))
    }

    func focusedGraph(_ overview: PortGraph, on id: String) -> PortGraph {
        let graph = overview.focused(on: id)
        let listeners = graph.nodes.compactMap(\.port).map { port in (port, ports.ports.first { $0.port == port }?.processName ?? "") }
        return graph.removing { node in
            guard case .pluginNode(let id) = node.kind, !graph.edges.contains(where: { $0.to == node.id }) else { return false }
            guard let action = plugins.nodes.node(id).flatMap(plugins.pluginAction(for:))?.action else { return true }
            return !listeners.contains { action.applies(toPort: $0.0, processName: $0.1) }
        }
    }

    var portForNewNode: Int? {
        if let focusedPort { return focusedPort }
        switch selection {
        case .process(let pid):
            let numbers = ports.ports.filter { $0.pid == pid }.map(\.port)
            return numbers.count == 1 ? numbers.first : nil
        case .inactivePort(let port):
            return port
        default:
            return nil
        }
    }

    func apply(_ change: GraphChange) {
        switch change {
        case .favorite(let port):
            preferences.favorites.insert(port)
        case .unfavorite(let port):
            preferences.favorites.remove(port)
        case .watch(let port):
            if !preferences.isWatching(port) { preferences.toggleWatch(port) }
        case .unwatch(let port):
            if preferences.isWatching(port) { preferences.toggleWatch(port) }
        case .share(let port):
            tunnels.startQuickTunnel(port: port)
        case .stopSharing(let id):
            if let tunnel = tunnels.quickTunnels.first(where: { $0.id == id }) { tunnels.stopQuickTunnel(tunnel) }
        case .connectPluginNode(let id, let port):
            plugins.connect(id, to: port)
        case .disconnectPluginNode(let id, let port):
            plugins.disconnect(id, from: port)
        }
    }

    func select(_ node: GraphNode) {
        switch node.kind {
        case .port(let port):
            if let listener = ports.ports.first(where: { $0.port == port }) {
                selection = .process(listener.pid)
                focusedPort = port
            } else {
                selection = .inactivePort(port)
            }
        case .pluginNode(let id):
            if let run = plugins.activity.latest(node: id), !run.isRunning {
                plugins.presentedRun = run
            }
        default:
            if let item = node.kind.itemID {
                selection = item
                focusedPort = nil
            }
        }
    }

    func isSelected(_ node: GraphNode) -> Bool {
        if let focusedPort { return node.kind == .port(focusedPort) }
        return node.kind.itemID.map { $0 == selection } ?? false
    }

    func graphLayout(_ key: String) -> [String: GraphPoint] {
        graphOffsets[key] ?? [:]
    }

    func moveGraphNode(_ id: String, by translation: CGSize, in key: String) {
        guard hypot(translation.width, translation.height) >= 12 else { return }
        let offset = graphOffsets[key]?[id] ?? GraphPoint(x: 0, y: 0)
        graphOffsets[key, default: [:]][id] = GraphPoint(x: offset.x + translation.width, y: offset.y + translation.height)
        UserDefaults.standard.setEncodedValue(graphOffsets, forKey: "graphOffsets")
    }

    func resetGraphLayout(_ key: String) {
        graphOffsets[key] = nil
        UserDefaults.standard.setEncodedValue(graphOffsets, forKey: "graphOffsets")
        graphZoomRequest = GraphZoomRequest(kind: .fit)
    }
}

extension GraphNode.Kind {
    var itemID: ItemID? {
        switch self {
        case .process(let pid): .process(pid)
        case .forward(let id): .forward(id)
        case .pluginItem(let plugin, let item), .pluginTarget(let plugin, let item): .pluginItem(plugin: plugin, item: item)
        case .port(let port): .inactivePort(port)
        case .quickTunnel(let id): .quickTunnel(id)
        case .namedTunnel(let id): .namedTunnel(id)
        case .favorites, .watch, .share, .autoKill, .pluginNode: nil
        }
    }
}
