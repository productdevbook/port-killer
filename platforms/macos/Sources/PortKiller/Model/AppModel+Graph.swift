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
                    subtitle: item.label ?? item.category.rawValue,
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
                node: GraphNode(id: "favorites", kind: .favorites, title: "Favorites", subtitle: "Keep ports at hand", symbol: "star"),
                ports: preferences.favorites.sorted(),
                origin: .link
            ),
            PortGraph.Consumer(
                node: GraphNode(id: "watch", kind: .watch, title: "Watch", subtitle: "Notify on start and stop", symbol: "eye"),
                ports: preferences.watchedPorts.map(\.port),
                origin: .link
            ),
        ]
        if tunnels.isInstalled {
            consumers.append(PortGraph.Consumer(
                node: GraphNode(id: "share", kind: .share, title: "Quick Tunnel", subtitle: "Share on a public URL", symbol: "bolt"),
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
                    isActive: tunnel.status == .active
                ),
                ports: [tunnel.port],
                origin: .link
            )
        }
        consumers += tunnels.namedTunnels.filter(\.isRunningHere).map { tunnel in
            PortGraph.Consumer(
                node: GraphNode(id: "tunnel:\(tunnel.id)", kind: .namedTunnel(tunnel.id), title: tunnel.name, subtitle: tunnel.statusTitle, symbol: "cloud"),
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
                    subtitle: "Stops after \(rule.timeoutMinutes) min",
                    symbol: "timer"
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
                        subtitle: item.subtitle ?? plugin.manifest.name,
                        symbol: plugin.manifest.icon ?? "puzzlepiece.extension",
                        isActive: item.status != .stopped
                    ),
                    ports: targets,
                    origin: .system
                ))
            }
        }
        for plugin in plugins.enabledPlugins {
            for action in plugin.manifest.portActions ?? [] {
                consumers.append(PortGraph.Consumer(
                    node: GraphNode(
                        id: "action:\(plugin.id):\(action.id)",
                        kind: .pluginAction(plugin: plugin.id, action: action.id),
                        title: action.title,
                        subtitle: plugin.manifest.name,
                        symbol: action.icon ?? plugin.manifest.icon ?? "puzzlepiece.extension"
                    ),
                    ports: [],
                    origin: .link
                ))
            }
        }
        return PortGraph(providers: providers, consumers: consumers, idlePorts: Set(ports.inactivePorts(for: portScope)))
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
        case .runPluginAction(let pluginID, let actionID, let port):
            guard let plugin = plugins.enabledPlugins.first(where: { $0.id == pluginID }),
                  let action = plugin.manifest.portActions?.first(where: { $0.id == actionID }),
                  let listener = ports.ports.first(where: { $0.port == port })
            else { return }
            plugins.run(action, on: listener, in: plugin)
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
        case .pluginAction(let plugin, let action):
            if let run = plugins.activity.latest(plugin: plugin, action: action), !run.isRunning {
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
        graphLayouts[key] ?? [:]
    }

    func saveGraphPosition(_ point: GraphPoint, for id: String, in key: String) {
        graphLayouts[key, default: [:]][id] = point
        UserDefaults.standard.setEncodedValue(graphLayouts, forKey: "graphLayouts")
    }

    func resetGraphLayout(_ key: String) {
        graphLayouts[key] = nil
        UserDefaults.standard.setEncodedValue(graphLayouts, forKey: "graphLayouts")
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
        case .favorites, .watch, .share, .autoKill, .pluginAction: nil
        }
    }
}
