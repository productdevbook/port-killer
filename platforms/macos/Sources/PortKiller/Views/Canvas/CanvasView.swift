import AppKit
import PortKillerKit
import SwiftUI

struct CanvasView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), ignoresSafeAreaEdges: .all)
            .toolbar { CanvasToolbar(model: model) }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .scrollEdgeEffectHidden(true, for: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch model.selection {
        case .process(let pid):
            if let item = model.ports.process(pid: pid) {
                ProcessCanvas(item: item)
            } else {
                NoSelectionCanvas()
            }
        case .inactivePort(let port):
            InactivePortCanvas(port: port)
        case .forward(let id):
            if let session = model.forwards.sessions.first(where: { $0.id == id }) {
                ForwardCanvas(session: session)
            } else {
                NoSelectionCanvas()
            }
        case .quickTunnel(let id):
            if let tunnel = model.tunnels.quickTunnels.first(where: { $0.id == id }) {
                QuickTunnelCanvas(tunnel: tunnel)
            } else {
                NoSelectionCanvas()
            }
        case .namedTunnel(let id):
            if let tunnel = model.tunnels.namedTunnels.first(where: { $0.id == id }) {
                NamedTunnelCanvas(tunnel: tunnel)
            } else {
                NoSelectionCanvas()
            }
        case .pluginItem(let pluginID, let itemID):
            if let plugin = model.plugins.itemPlugins.first(where: { $0.id == pluginID }),
               let item = model.plugins.items[pluginID]?.first(where: { $0.id == itemID }) {
                PluginItemCanvas(plugin: plugin, item: item)
            } else {
                NoSelectionCanvas()
            }
        case nil:
            NoSelectionCanvas()
        }
    }
}

private struct CanvasToolbar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        let ports = model.selectedPorts
        let preferences = model.preferences
        let url = model.selectedURL
        ToolbarItemGroup {
            Toggle(isOn: Binding(
                get: { !ports.isEmpty && ports.allSatisfy { preferences.favorites.contains($0) } },
                set: { isOn in
                    for port in ports {
                        if isOn {
                            preferences.favorites.insert(port)
                        } else {
                            preferences.favorites.remove(port)
                        }
                    }
                }
            )) {
                Label("Favorite", systemImage: "star")
            }
            .help("Keep this port in Favorites")
            .disabled(ports.isEmpty)
            Toggle(isOn: Binding(
                get: { !ports.isEmpty && ports.allSatisfy { preferences.isWatching($0) } },
                set: { isOn in
                    for port in ports where preferences.isWatching(port) != isOn {
                        preferences.toggleWatch(port)
                    }
                }
            )) {
                Label("Watch", systemImage: "eye")
            }
            .help("Notify when this port starts or stops being used")
            .disabled(ports.isEmpty)
        }
        ToolbarItem {
            ControlGroup {
                Button("Open in Browser", systemImage: "safari") {
                    if let url { NSWorkspace.shared.open(url) }
                }
                .help("Open in Browser")
                Button("Copy URL", systemImage: "link") {
                    if let url { Pasteboard.copy(url.absoluteString) }
                }
                .help("Copy URL")
            }
            .controlGroupStyle(.navigation)
            .disabled(url == nil)
        }
        ToolbarItem {
            Menu {
                if let selection = model.selection {
                    ItemActions(id: selection)
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuIndicator(.hidden)
            .disabled(model.selection == nil)
        }
    }
}

struct ItemCanvas<Artwork: View, Accessory: View>: View {
    let title: String
    let subtitle: String
    var message: String?
    @ViewBuilder var artwork: Artwork
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: 0) {
            artwork
                .frame(maxWidth: 240, maxHeight: 240)
                .padding(.bottom, 36)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 4)
            HStack(spacing: 8) {
                accessory
            }
            .padding(.top, 22)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: 420)
                    .padding(.top, 14)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ItemArtwork: View {
    let symbol: String
    var process: ProcessSnapshot?

    var body: some View {
        if let image = AppIcons.shared.image(for: process, pixels: 512) {
            Image(decorative: image, scale: 2)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.ultraLight)
                .foregroundStyle(.tertiary)
                .padding(24)
        }
    }
}

struct CanvasButton: View {
    let title: String
    let symbol: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

struct ControlsBar<Controls: View, Primary: View>: View {
    @ViewBuilder var controls: Controls
    @ViewBuilder var primary: Primary

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    controls
                }
                .padding(.horizontal, 5)
                .glassEffect(.regular.interactive(), in: .capsule)
                primary
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.bottom, 14)
    }
}

struct ControlButton: View {
    let title: String
    let symbol: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(tint ?? .primary)
                .frame(width: 34, height: 36)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct NoSelectionCanvas: View {
    var body: some View {
        ContentUnavailableView("No Selection", systemImage: "network", description: Text("Select a port, port forward or tunnel in the sidebar."))
            .navigationTitle("PortKiller")
    }
}

private struct ProcessCanvas: View {
    @Environment(AppModel.self) private var model
    let item: ProcessItem

    var body: some View {
        let isTerminating = model.ports.terminating.contains(item.process.pid)
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ItemArtwork(symbol: item.category.symbolName, process: item.process)
                        .frame(width: 96, height: 96)
                        .padding(.bottom, 20)
                    Text(item.process.name)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text("PID \(String(item.process.pid)) · \(item.category.rawValue) · \(item.process.user)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    HStack(spacing: 8) {
                        if isTerminating {
                            ProgressView().controlSize(.small)
                            Text("Stopping…").foregroundStyle(.secondary)
                        } else {
                            CanvasButton(title: "Kill Process", symbol: "xmark.octagon", role: .destructive) {
                                model.ports.requestKill(item.ports)
                            }
                        }
                    }
                    .padding(.top, 20)
                    PortsCard(item: item)
                        .frame(maxWidth: 620)
                        .padding(.top, 32)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle(item.process.name)
        .navigationSubtitle(item.ports.count == 1 ? "1 port" : "\(item.ports.count) ports")
    }
}

private struct PortsCard: View {
    @Environment(AppModel.self) private var model
    let item: ProcessItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.ports.count == 1 ? "Port" : "Ports")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
            VStack(spacing: 0) {
                ForEach(Array(item.ports.enumerated()), id: \.element.id) { index, port in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 56)
                    }
                    PortCardRow(port: port, siblings: item.ports.count - 1)
                }
            }
            .background(.fill.quaternary, in: .rect(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct PortCardRow: View {
    @Environment(AppModel.self) private var model
    let port: ListeningPort
    let siblings: Int
    @State private var hovering = false

    var body: some View {
        let preferences = model.preferences
        let tunnels = model.tunnels
        let quickTunnel = tunnels.quickTunnel(for: port.port)
        let isSharing = quickTunnel.map { $0.status != .failed } ?? false
        let isFocused = model.focusedPort == port.port
        let label = preferences.label(for: port.port)
        HStack(spacing: 12) {
            Image(systemName: port.isLoopbackOnly ? "lock" : "network")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14))
                .foregroundStyle(isFocused ? Color.accentColor : .secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.background))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(String(port.port))
                        .font(.body.monospacedDigit().weight(.semibold))
                    if preferences.favorites.contains(port.port) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                    if preferences.isWatching(port.port) {
                        Image(systemName: "eye.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    if isSharing || tunnels.exposuresByPort[port.port] != nil {
                        Image(systemName: "globe").font(.caption2).foregroundStyle(.orange)
                    }
                }
                Text([label, addressDescription].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                RowButton(title: "Open in Browser", symbol: "safari") {
                    if let url = port.localURL { NSWorkspace.shared.open(url) }
                }
                RowButton(title: isSharing ? "Stop Sharing" : "Share with Quick Tunnel", symbol: isSharing ? "bolt.fill" : "bolt", tint: isSharing ? .orange : nil) {
                    if let quickTunnel, isSharing {
                        tunnels.stopQuickTunnel(quickTunnel)
                    } else {
                        tunnels.startQuickTunnel(port: port.port)
                    }
                }
                .disabled(!tunnels.isInstalled && !isSharing)
                Menu {
                    PortMenu(port: port, siblings: siblings)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.borderless)
                .fixedSize()
                .help("More")
                RowButton(title: siblings > 0 ? "Kill the process to free port \(port.port)" : "Kill Process", symbol: "xmark.circle", tint: hovering ? .red : nil) {
                    model.ports.requestKill([port])
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isFocused ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.clear))
        .contentShape(.rect)
        .onTapGesture {
            model.focusedPort = isFocused ? nil : port.port
        }
        .onHover { hovering = $0 }
        .contextMenu {
            PortMenu(port: port, siblings: siblings)
        }
    }
}

private extension PortCardRow {
    var addressDescription: String {
        let addresses = port.addresses.map { $0 == "*" ? "All interfaces" : $0 }.joined(separator: ", ")
        return port.isLoopbackOnly ? "\(addresses) · This Mac only" : addresses
    }
}

private struct PortMenu: View {
    @Environment(AppModel.self) private var model
    let port: ListeningPort
    let siblings: Int

    var body: some View {
        let preferences = model.preferences
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
        Button("Edit Label and Note…", systemImage: "tag") {
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

private struct RowButton: View {
    let title: String
    let symbol: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct InactivePortCanvas: View {
    @Environment(AppModel.self) private var model
    let port: Int

    var body: some View {
        ItemCanvas(title: "Port \(String(port))", subtitle: "Nothing listens on this port right now.") {
            ItemArtwork(symbol: "moon.zzz")
        } accessory: {
            CanvasButton(title: "Remove", symbol: "minus.circle") {
                model.ports.removeInactive(port)
            }
        }
        .navigationTitle("Port \(String(port))")
        .navigationSubtitle("Not Running")
    }
}

private struct ForwardCanvas: View {
    let session: PortForwardSession

    var body: some View {
        let configuration = session.configuration
        ItemCanvas(
            title: configuration.name,
            subtitle: "\(configuration.target) → localhost:\(String(configuration.effectivePort))",
            message: session.status == .connected ? nil : session.lastError
        ) {
            ItemArtwork(symbol: "point.3.connected.trianglepath.dotted")
        } accessory: {
            switch session.status {
            case .stopped, .failed:
                CanvasButton(title: "Start", symbol: "play.fill") { session.start() }
            case .connecting, .waitingToReconnect, .stopping:
                ProgressView().controlSize(.small)
                Text(session.status.title).foregroundStyle(.secondary)
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .overlay(alignment: .bottom) {
            if session.isActive {
                ControlsBar {
                    ControlButton(title: "Open in Browser", symbol: "safari") {
                        if let url = configuration.localURL { NSWorkspace.shared.open(url) }
                    }
                    ControlButton(title: "Copy URL", symbol: "link") {
                        if let url = configuration.localURL { Pasteboard.copy(url.absoluteString) }
                    }
                    ControlButton(title: "Restart", symbol: "arrow.clockwise") { session.restart() }
                } primary: {
                    ControlButton(title: "Stop", symbol: "stop.fill", tint: .red) { session.stop() }
                }
            }
        }
        .navigationTitle(configuration.name)
        .navigationSubtitle(session.status.title)
    }
}

private struct QuickTunnelCanvas: View {
    @Environment(AppModel.self) private var model
    let tunnel: QuickTunnel

    var body: some View {
        ItemCanvas(
            title: tunnel.host ?? "Quick Tunnel",
            subtitle: "Shares localhost:\(String(tunnel.port)) on a public address",
            message: tunnel.status == .active ? nil : tunnel.lastError
        ) {
            ItemArtwork(symbol: "bolt")
        } accessory: {
            switch tunnel.status {
            case .starting, .stopping:
                ProgressView().controlSize(.small)
                Text(tunnel.status.title).foregroundStyle(.secondary)
            case .active:
                Label("Active", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                CanvasButton(title: "Dismiss", symbol: "xmark") { model.tunnels.stopQuickTunnel(tunnel) }
            }
        }
        .overlay(alignment: .bottom) {
            if let url = tunnel.url {
                ControlsBar {
                    ControlButton(title: "Open in Browser", symbol: "safari") { NSWorkspace.shared.open(url) }
                    ControlButton(title: "Copy URL", symbol: "link") { Pasteboard.copy(url.absoluteString) }
                } primary: {
                    ControlButton(title: "Stop Sharing", symbol: "stop.fill", tint: .red) { model.tunnels.stopQuickTunnel(tunnel) }
                }
            }
        }
        .navigationTitle(tunnel.host ?? "Quick Tunnel")
        .navigationSubtitle("Port \(String(tunnel.port))")
    }
}

private struct NamedTunnelCanvas: View {
    @Environment(AppModel.self) private var model
    let tunnel: NamedTunnel

    var body: some View {
        let tunnels = model.tunnels
        let url = tunnel.publicURLs.first.flatMap(URL.init(string:))
        ItemCanvas(
            title: tunnel.name,
            subtitle: tunnel.publicURLs.first ?? tunnel.statusTitle,
            message: tunnel.isRunningHere ? nil : tunnel.lastError
        ) {
            ItemArtwork(symbol: "cloud")
        } accessory: {
            switch tunnel.status {
            case .starting, .stopping:
                ProgressView().controlSize(.small)
                Text(tunnel.statusTitle).foregroundStyle(.secondary)
            case .running:
                Label(tunnel.statusTitle, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .stopped, .failed:
                CanvasButton(title: tunnel.runSafety == .managedElsewhere ? "Run Anyway" : "Run", symbol: "play.fill") {
                    tunnels.run(tunnel, allowManagedElsewhere: tunnel.runSafety == .managedElsewhere)
                }
                .disabled(!tunnels.isInstalled)
            }
        }
        .overlay(alignment: .bottom) {
            if tunnel.status == .running {
                ControlsBar {
                    ControlButton(title: "Open in Browser", symbol: "safari") {
                        if let url { NSWorkspace.shared.open(url) }
                    }
                    .disabled(url == nil)
                    ControlButton(title: "Copy Tunnel ID", symbol: "number") { Pasteboard.copy(tunnel.id) }
                } primary: {
                    ControlButton(title: "Stop", symbol: "stop.fill", tint: .red) { tunnels.stop(tunnel) }
                }
            }
        }
        .navigationTitle(tunnel.name)
        .navigationSubtitle(tunnel.statusTitle)
    }
}

private struct PluginItemCanvas: View {
    @Environment(AppModel.self) private var model
    let plugin: Plugin
    let item: PluginItem

    var body: some View {
        let store = model.plugins
        ItemCanvas(title: item.title, subtitle: item.subtitle ?? item.status.title) {
            ItemArtwork(symbol: plugin.manifest.icon ?? "puzzlepiece.extension")
        } accessory: {
            ForEach(item.actions ?? []) { action in
                CanvasButton(title: action.title, symbol: action.icon ?? "circle", role: action.destructive == true ? .destructive : nil) {
                    Task { await store.perform(action, on: item, in: plugin) }
                }
                .disabled(store.isPerforming(action, on: item, in: plugin))
            }
        }
        .overlay(alignment: .bottom) {
            if let url = item.url {
                ControlsBar {
                    ControlButton(title: "Open in Browser", symbol: "safari") { NSWorkspace.shared.open(url) }
                    ControlButton(title: "Copy URL", symbol: "link") { Pasteboard.copy(url.absoluteString) }
                } primary: {
                    ControlButton(title: "Refresh", symbol: "arrow.clockwise") {
                        Task { await store.refresh(plugin) }
                    }
                }
            }
        }
        .navigationTitle(item.title)
        .navigationSubtitle(plugin.manifest.name)
    }
}
