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
    let onMoveChanged: (CGSize) -> Void
    let onMoveEnded: (CGSize) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if pins.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    description
                    Divider()
                        .padding(.horizontal, 14)
                    status
                }
                .modifier(NodeInteraction(node: node, graph: graph, onMoveChanged: onMoveChanged, onMoveEnded: onMoveEnded))
            } else {
                header
                    .modifier(NodeInteraction(node: node, graph: graph, onMoveChanged: onMoveChanged, onMoveEnded: onMoveEnded))
                Divider()
                ForEach(pins) { pin in
                    PinRow(
                        pin: pin,
                        owner: node,
                        graph: graph,
                        isSelected: selected.contains(pin.id) && pin.id != node.id,
                        onLinkChanged: onLinkChanged,
                        onLinkEnded: onLinkEnded
                    )
                }
                Spacer(minLength: GraphMetrics.footer)
            }
        }
        .frame(width: GraphMetrics.width, height: GraphMetrics.height(pins: pins.count), alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor), in: shape)
        .overlay { shape.strokeBorder(borderColor, lineWidth: borderWidth) }
        .overlay(alignment: .topLeading) {
            if node.column == .consumers {
                PinCircle(tint: connections > 0 ? node.kind.tint : Color(nsColor: .tertiaryLabelColor), isFilled: connections > 0 || linkState == .target, isEmphasized: linkState == .target)
                    .offset(x: -GraphMetrics.pin / 2, y: (GraphMetrics.header - GraphMetrics.pin) / 2)
                    .allowsHitTesting(false)
            }
        }
        .opacity(linkState == .dimmed ? 0.4 : node.isActive ? 1 : 0.6)
        .animation(.snappy(duration: 0.2), value: linkState)
    }

    private var header: some View {
        HStack(spacing: 12) {
            NodeIcon(node: node)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.port.map { "Port \(String($0))" } ?? node.title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(kindTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: GraphMetrics.header)
    }

    private var description: some View {
        Text(node.detail)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: GraphMetrics.detail, maxHeight: GraphMetrics.detail, alignment: .topLeading)
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 6) {
            if case .pluginAction(let plugin, let action) = node.kind, let run = model.plugins.activity.latest(plugin: plugin, action: action) {
                PluginRunStatus(run: run)
                    .controlSize(.mini)
                Text(run.summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if connections > 0 {
                Image(systemName: "link")
                    .foregroundStyle(node.kind.tint)
                Text(connectedPorts)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if node.acceptsLinks {
                Image(systemName: "arrow.left")
                    .foregroundStyle(.tertiary)
                Text(node.kind.isPluginAction ? "Drag a port here to run it" : "Drag a port here")
                    .foregroundStyle(.tertiary)
            } else {
                Text("No ports")
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .frame(height: GraphMetrics.status)
    }

    private var kindTitle: String {
        if let port = node.port {
            return model.preferences.label(for: port) ?? node.subtitle
        }
        return node.subtitle
    }

    private var connections: Int {
        graph.edges.count { $0.to == node.id }
    }

    private var connectedPorts: String {
        let ports = graph.edges.filter { $0.to == node.id }.compactMap { graph.node(id: $0.from)?.port }.map(String.init)
        return ports.count == 1 ? "Port \(ports[0])" : "Ports \(ports.prefix(4).joined(separator: ", "))\(ports.count > 4 ? " +\(ports.count - 4)" : "")"
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

private struct NodeInteraction: ViewModifier {
    @Environment(AppModel.self) private var model
    let node: GraphNode
    let graph: PortGraph
    let onMoveChanged: (CGSize) -> Void
    let onMoveEnded: (CGSize) -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .pointerStyle(.grabIdle)
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named(GraphCanvas.space))
                    .onChanged { onMoveChanged($0.translation) }
                    .onEnded { onMoveEnded($0.translation) }
            )
            .onTapGesture { model.select(node) }
            .contextMenu { GraphNodeMenu(node: node, graph: graph) }
    }
}

private struct NodeIcon: View {
    @Environment(AppModel.self) private var model
    let node: GraphNode

    var body: some View {
        if case .process(let pid) = node.kind, let image = AppIcons.shared.image(for: model.ports.process(pid: pid)?.process, pixels: 64) {
            Image(decorative: image, scale: 2)
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
        } else {
            Image(systemName: node.port == nil ? node.symbol : "moon.zzz.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(node.port == nil ? node.kind.tint.gradient : Color.gray.gradient, in: .rect(cornerRadius: 10, style: .continuous))
        }
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
    @State private var linking = false

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
        .padding(.trailing, 24)
        .frame(height: GraphMetrics.pin)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : hovering ? Color.primary.opacity(0.05) : .clear)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .contentShape(.rect)
        .overlay(alignment: .trailing) {
            PinCircle(tint: .accentColor, isFilled: linking || graph.edges.contains { $0.from == pin.id }, isEmphasized: hovering || linking)
                .offset(x: GraphMetrics.pin / 2)
        }
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(GraphCanvas.space))
                .onChanged { value in
                    linking = true
                    onLinkChanged(port, value.location)
                }
                .onEnded { _ in
                    linking = false
                    onLinkEnded()
                }
        )
        .onTapGesture { model.select(pin) }
        .contextMenu { GraphNodeMenu(node: pin, graph: graph) }
        .help("Click to select port \(String(port)). Drag to connect it.")
    }

    private func listener(_ port: Int) -> ListeningPort? {
        if case .process(let pid) = owner.kind {
            return model.ports.ports.first { $0.port == port && $0.pid == pid }
        }
        return model.ports.ports.first { $0.port == port }
    }

    private static func addresses(_ port: ListeningPort) -> String {
        port.isLoopbackOnly ? "This Mac only" : port.addresses.map { $0 == "*" ? "All interfaces" : $0 }.joined(separator: ", ")
    }
}

private struct PinCircle: View {
    let tint: Color
    let isFilled: Bool
    let isEmphasized: Bool

    var body: some View {
        let size: CGFloat = isEmphasized ? 22 : 18
        Circle()
            .fill(isFilled ? tint : Color(nsColor: .controlBackgroundColor))
            .strokeBorder(tint, lineWidth: 3)
            .frame(width: size, height: size)
            .frame(width: GraphMetrics.pin, height: GraphMetrics.pin)
            .contentShape(.rect)
            .animation(.snappy(duration: 0.15), value: isEmphasized)
    }
}

extension GraphNode.Kind {
    var isPluginAction: Bool {
        if case .pluginAction = self { true } else { false }
    }

    var tint: Color {
        switch self {
        case .favorites: .yellow
        case .watch: .blue
        case .share, .quickTunnel, .namedTunnel: .orange
        case .autoKill: .red
        case .pluginItem, .pluginAction, .pluginTarget: .purple
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
        case .pluginTarget(let plugin, let item):
            ItemActions(id: .pluginItem(plugin: plugin, item: item))
        case .pluginAction(let plugin, let action):
            if let run = model.plugins.activity.latest(plugin: plugin, action: action) {
                Button("Show Last Result", systemImage: "doc.text.magnifyingglass") { model.plugins.presentedRun = run }
                    .disabled(run.isRunning)
            }
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
        case .favorites, .watch, .share, .autoKill:
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
                    model.plugins.run(entry.action, on: port, in: entry.plugin)
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
