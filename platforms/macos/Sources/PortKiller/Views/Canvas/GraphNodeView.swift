import AppKit
import PortKillerKit
import SwiftUI

struct GraphNodeView: View {
    @Environment(AppModel.self) private var model
    let node: GraphNode
    let isSelected: Bool
    let isLinkTarget: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(node.title)
                    .font(node.port == nil ? .title3.weight(.semibold) : .title2.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: GraphCanvas.nodeSize.width, height: GraphCanvas.nodeSize.height)
        .background(Color(nsColor: .controlBackgroundColor), in: shape)
        .overlay {
            shape.strokeBorder(isSelected || isLinkTarget ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected || isLinkTarget ? 2 : 1)
        }
        .overlay(alignment: .leading) {
            if node.column != .providers {
                Socket().offset(x: -5)
            }
        }
        .overlay(alignment: .trailing) {
            if node.column == .providers {
                Socket().offset(x: 5)
            }
        }
        .opacity(node.isActive ? 1 : 0.6)
        .contentShape(shape)
    }

    @ViewBuilder
    private var icon: some View {
        switch node.kind {
        case .process(let pid):
            ItemIcon(symbol: node.symbol, process: model.ports.process(pid: pid)?.process)
        case .port:
            StatusDot(color: node.isActive ? .green : Color(nsColor: .tertiaryLabelColor), size: 9)
                .frame(width: 20)
        default:
            ItemIcon(symbol: node.symbol, tint: tint)
        }
    }

    private var tint: Color {
        switch node.kind {
        case .favorites: .yellow
        case .watch: .blue
        case .share, .quickTunnel, .namedTunnel: .orange
        case .autoKill: .red
        case .pluginItem, .pluginAction: .purple
        default: .accentColor
        }
    }

    private var subtitle: String {
        guard let port = node.port else { return node.subtitle }
        return model.preferences.label(for: port) ?? node.subtitle
    }
}

private struct Socket: View {
    var body: some View {
        Circle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .strokeBorder(Color(nsColor: .tertiaryLabelColor), lineWidth: 1.5)
            .frame(width: 10, height: 10)
    }
}

struct GraphNodeMenu: View {
    @Environment(AppModel.self) private var model
    let node: GraphNode
    let graph: PortGraph

    var body: some View {
        switch node.kind {
        case .process(let pid):
            ItemActions(id: .process(pid))
        case .forward(let id):
            ItemActions(id: .forward(id))
        case .pluginItem(let plugin, let item):
            ItemActions(id: .pluginItem(plugin: plugin, item: item))
        case .quickTunnel(let id):
            ItemActions(id: .quickTunnel(id))
        case .namedTunnel(let id):
            ItemActions(id: .namedTunnel(id))
        case .port(let port):
            if let listener = model.ports.ports.first(where: { $0.port == port }) {
                PortMenu(port: listener)
            } else {
                let preferences = model.preferences
                Button(preferences.favorites.contains(port) ? "Remove from Favorites" : "Add to Favorites", systemImage: "star") {
                    preferences.toggleFavorite(port)
                }
                Button(preferences.isWatching(port) ? "Stop Watching" : "Watch", systemImage: "eye") {
                    preferences.toggleWatch(port)
                }
            }
            DisconnectMenu(node: node, graph: graph)
        case .favorites, .watch, .share, .autoKill, .pluginAction:
            DisconnectMenu(node: node, graph: graph)
        }
    }
}

private struct DisconnectMenu: View {
    @Environment(AppModel.self) private var model
    let node: GraphNode
    let graph: PortGraph

    var body: some View {
        let changes = graph.edges
            .filter { $0.from == node.id || $0.to == node.id }
            .compactMap { edge in
                graph.change(unlinking: edge).map { (title: disconnectTitle(edge), change: $0) }
            }
        if !changes.isEmpty {
            Divider()
            Menu("Disconnect", systemImage: "link") {
                ForEach(changes, id: \.change) { entry in
                    Button(entry.title) { model.apply(entry.change) }
                }
            }
        }
    }

    private func disconnectTitle(_ edge: GraphEdge) -> String {
        let other = graph.node(id: edge.from == node.id ? edge.to : edge.from)
        guard let other else { return edge.id }
        return other.port.map { "Port \(String($0))" } ?? other.title
    }
}

struct PortMenu: View {
    @Environment(AppModel.self) private var model
    let port: ListeningPort

    var body: some View {
        let preferences = model.preferences
        let siblings = model.ports.ports.filter { $0.pid == port.pid && $0.port != port.port }.count
        if let url = port.localURL {
            URLActions(url: url)
            Divider()
        }
        Button(preferences.favorites.contains(port.port) ? "Remove from Favorites" : "Add to Favorites", systemImage: "star") {
            preferences.toggleFavorite(port.port)
        }
        Button(preferences.isWatching(port.port) ? "Stop Watching" : "Watch", systemImage: "eye") {
            preferences.toggleWatch(port.port)
        }
        if let tunnel = model.tunnels.quickTunnel(for: port.port) {
            Button("Stop Sharing", systemImage: "bolt.slash") { model.tunnels.stopQuickTunnel(tunnel) }
        } else if model.tunnels.isInstalled {
            Button("Share with Quick Tunnel", systemImage: "bolt") { model.tunnels.startQuickTunnel(port: port.port) }
        }
        Button("Edit Label and Note…", systemImage: "tag") {
            model.selection = .process(port.pid)
            model.focusedPort = port.port
            model.inspectorTab = .settings
            model.inspectorVisible = true
        }
        let actions = model.plugins.portActions(for: port)
        if !actions.isEmpty {
            Divider()
            ForEach(Array(actions.enumerated()), id: \.offset) { _, entry in
                Button(entry.action.title, systemImage: entry.action.icon ?? entry.plugin.manifest.icon ?? "puzzlepiece.extension") {
                    Task { await model.plugins.perform(entry.action, on: port, in: entry.plugin) }
                }
            }
        }
        Divider()
        Button("Kill and Close Connections", systemImage: "bolt.horizontal.circle", role: .destructive) {
            Task { await model.ports.kill([port], mode: .deep) }
        }
        Button(siblings > 0 ? "Kill Process to Free Port \(String(port.port))…" : "Kill Process…", systemImage: "xmark.octagon", role: .destructive) {
            model.ports.requestKill([port])
        }
    }
}
