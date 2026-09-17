import AppKit
import PortKillerKit
import SwiftUI

struct GraphBlockView: View {
    enum LinkState {
        case idle
        case candidate
        case target
        case dimmed
    }

    @Environment(AppModel.self) private var model
    let node: GraphNode
    let pins: [GraphNode]
    let graph: PortGraph
    let selected: Set<String>
    let linkState: LinkState
    let onLinkChanged: (Int, CGPoint) -> Void
    let onLinkEnded: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let tint = node.kind.tint
        VStack(spacing: 0) {
            header
                .frame(height: GraphMetrics.header)
                .background(tint.opacity(0.08), in: UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: pins.isEmpty ? 14 : 0,
                    bottomTrailingRadius: pins.isEmpty ? 14 : 0,
                    topTrailingRadius: 14,
                    style: .continuous
                ))
                .overlay(alignment: .bottom) {
                    if !pins.isEmpty { Divider() }
                }
                .overlay(alignment: .trailing) {
                    if let port = node.port {
                        PinHandle(port: port, tint: .accentColor, onChanged: onLinkChanged, onEnded: onLinkEnded)
                    }
                }
                .contentShape(.rect)
                .onTapGesture { model.select(node) }
                .contextMenu { GraphNodeMenu(node: node, graph: graph) }
            if !pins.isEmpty {
                ForEach(pins) { pin in
                    PinRow(pin: pin, owner: node, graph: graph, isSelected: selected.contains(pin.id), onLinkChanged: onLinkChanged, onLinkEnded: onLinkEnded)
                }
                Spacer(minLength: GraphMetrics.footer)
            }
        }
        .frame(width: GraphMetrics.width, height: GraphMetrics.height(pins: pins.count), alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor), in: shape)
        .overlay { shape.strokeBorder(borderColor, lineWidth: borderWidth) }
        .overlay(alignment: .topLeading) {
            if node.column == .consumers {
                Circle()
                    .fill(connections > 0 ? tint : Color(nsColor: .controlBackgroundColor))
                    .strokeBorder(connections > 0 ? tint : Color(nsColor: .tertiaryLabelColor), lineWidth: 2)
                    .frame(width: 12, height: 12)
                    .offset(x: -6, y: GraphMetrics.header / 2 - 6)
            }
        }
        .opacity(linkState == .dimmed ? 0.4 : node.isActive ? 1 : 0.6)
        .animation(.snappy(duration: 0.2), value: linkState)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            switch node.kind {
            case .process(let pid):
                ItemIcon(symbol: node.symbol, process: model.ports.process(pid: pid)?.process)
            case .port:
                StatusDot(color: node.isActive ? .green : Color(nsColor: .tertiaryLabelColor), size: 9)
                    .frame(width: 34)
            default:
                ItemIcon(symbol: node.symbol, tint: node.kind.tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(node.title)
                    .font(node.port == nil ? .title3.weight(.semibold) : .title3.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private var connections: Int {
        graph.edges.count { $0.to == node.id }
    }

    private var subtitle: String {
        if let port = node.port {
            return model.preferences.label(for: port) ?? node.subtitle
        }
        guard node.acceptsLinks else { return node.subtitle }
        return switch connections {
        case 0: "Drag a port here"
        case 1: "1 port"
        default: "\(connections) ports"
        }
    }

    private var borderColor: Color {
        switch linkState {
        case .target: node.kind.tint
        case .candidate: node.kind.tint.opacity(0.5)
        case .idle, .dimmed: selected.contains(node.id) ? .accentColor : Color(nsColor: .separatorColor)
        }
    }

    private var borderWidth: CGFloat {
        linkState == .target || linkState == .candidate || selected.contains(node.id) ? 2 : 1
    }
}

private struct PinRow: View {
    @Environment(AppModel.self) private var model
    let pin: GraphNode
    let owner: GraphNode
    let graph: PortGraph
    let isSelected: Bool
    let onLinkChanged: (Int, CGPoint) -> Void
    let onLinkEnded: () -> Void
    @State private var hovering = false

    var body: some View {
        let port = pin.port ?? 0
        let listener = listener(port)
        HStack(spacing: 8) {
            StatusDot(color: pin.isActive ? .green : Color(nsColor: .tertiaryLabelColor))
            Text(pin.title)
                .font(.body.monospacedDigit().weight(.semibold))
            Text(model.preferences.label(for: port) ?? listener.map(Self.addresses) ?? pin.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if hovering, let listener {
                Button {
                    model.ports.requestKill([listener])
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Kill the process to free port \(String(port))")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 20)
        .frame(height: GraphMetrics.pin)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : hovering ? Color.primary.opacity(0.05) : .clear)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .overlay(alignment: .trailing) {
            PinHandle(port: port, tint: .accentColor, onChanged: onLinkChanged, onEnded: onLinkEnded)
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { model.select(pin) }
        .contextMenu { GraphNodeMenu(node: pin, graph: graph) }
    }

    private func listener(_ port: Int) -> ListeningPort? {
        if case .process(let pid) = owner.kind {
            return model.ports.ports.first { $0.port == port && $0.pid == pid }
        }
        return model.ports.ports.first { $0.port == port }
    }

    private static func addresses(_ port: ListeningPort) -> String {
        let addresses = port.addresses.map { $0 == "*" ? "All interfaces" : $0 }.joined(separator: ", ")
        return port.isLoopbackOnly ? "\(addresses) · This Mac only" : addresses
    }
}

private struct PinHandle: View {
    let port: Int
    let tint: Color
    let onChanged: (Int, CGPoint) -> Void
    let onEnded: () -> Void

    var body: some View {
        Circle()
            .fill(tint)
            .strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 2)
            .frame(width: 14, height: 14)
            .padding(6)
            .contentShape(.circle)
            .offset(x: 13)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(GraphCanvas.space))
                    .onChanged { onChanged(port, $0.location) }
                    .onEnded { _ in onEnded() }
            )
            .help("Drag to Favorites, Watch, Quick Tunnel or a plugin action")
    }
}

extension GraphNode.Kind {
    var tint: Color {
        switch self {
        case .favorites: .yellow
        case .watch: .blue
        case .share, .quickTunnel, .namedTunnel: .orange
        case .autoKill: .red
        case .pluginItem, .pluginAction: .purple
        case .process, .forward, .port: .accentColor
        }
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
