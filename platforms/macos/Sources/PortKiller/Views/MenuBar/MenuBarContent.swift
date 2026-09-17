import AppKit
import OrderedCollections
import PortKillerKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var confirmingKill: String?
    @State private var confirmingKillAll = false
    @State private var expanded: Set<String> = []

    var body: some View {
        let ports = visiblePorts
        let forwards = visibleForwards
        let quick = model.tunnels.quickTunnels
        let named = model.tunnels.namedTunnels.filter { $0.isRunningHere || $0.runSafety == .safe }
        VStack(spacing: 0) {
            header(count: ports.count)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    if ports.isEmpty, forwards.isEmpty, quick.isEmpty, named.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "No Listening Ports" : "No Results", systemImage: "network.slash")
                            .padding(.vertical, 60)
                    }
                    if !ports.isEmpty {
                        Section {
                            if model.preferences.useTreeView {
                                ForEach(groups(ports), id: \.name) { group in
                                    MenuProcessGroup(name: group.name, ports: group.ports, expanded: $expanded, confirmingKill: $confirmingKill)
                                }
                            } else {
                                ForEach(ports) { port in
                                    MenuPortRow(port: port, confirmingKill: $confirmingKill)
                                }
                            }
                        } header: {
                            MenuSectionHeader(title: "Local Ports", symbol: "network", tint: .green)
                        }
                    }
                    if !forwards.isEmpty {
                        Section {
                            ForEach(forwards) { MenuForwardRow(session: $0) }
                        } header: {
                            MenuSectionHeader(title: "Port Forwards", symbol: "point.3.connected.trianglepath.dotted", tint: .indigo)
                        }
                    }
                    if !quick.isEmpty {
                        Section {
                            ForEach(quick) { MenuQuickTunnelRow(tunnel: $0) }
                        } header: {
                            MenuSectionHeader(title: "Quick Tunnels", symbol: "bolt.fill", tint: .yellow)
                        }
                    }
                    if !named.isEmpty {
                        Section {
                            ForEach(named) { MenuNamedTunnelRow(tunnel: $0) }
                        } header: {
                            MenuSectionHeader(title: "My Tunnels", symbol: "cloud.fill", tint: .orange)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(height: 420)
            Divider()
            footer
        }
        .frame(width: 390)
        .task {
            await model.ports.refresh()
            model.tunnels.discoverIfNeeded()
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search ports and processes", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.quaternary, in: .capsule)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(10)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if confirmingKillAll {
                Text("Kill all \(visiblePorts.count) processes?")
                    .font(.callout)
                Spacer()
                Button("Cancel") { confirmingKillAll = false }
                    .buttonStyle(.glass)
                Button("Kill All", role: .destructive) {
                    confirmingKillAll = false
                    let targets = visiblePorts
                    Task { await model.ports.kill(targets) }
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
            } else {
                footerButton("Refresh", "arrow.clockwise", key: "r") {
                    Task { await model.ports.refresh() }
                }
                footerButton(model.preferences.useTreeView ? "Show as List" : "Group by Process", model.preferences.useTreeView ? "list.bullet" : "list.bullet.indent", key: "t") {
                    model.preferences.useTreeView.toggle()
                }
                footerButton("Kill All", "xmark.octagon", key: "k", tint: .red) {
                    if model.preferences.skipKillConfirmation {
                        let targets = visiblePorts
                        Task { await model.ports.kill(targets) }
                    } else {
                        confirmingKillAll = true
                    }
                }
                .disabled(visiblePorts.isEmpty)
                Spacer()
                footerButton("Open PortKiller", "macwindow", key: "o") {
                    model.show()
                }
                footerButton("Settings", "gearshape", key: ",") {
                    NSApp.activate()
                    openSettings()
                }
                footerButton("Quit PortKiller", "power", key: "q") {
                    NSApp.terminate(nil)
                }
            }
        }
        .controlSize(.large)
        .padding(10)
    }

    private func footerButton(_ title: String, _ symbol: String, key: KeyEquivalent, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .foregroundStyle(tint ?? .primary)
            .keyboardShortcut(key)
            .help(title)
    }

    private var visiblePorts: [ListeningPort] {
        let hideSystem = model.preferences.hideSystemProcesses
        let favorites = model.preferences.favorites
        let search = PortFilter(searchText: query)
        return model.ports.ports
            .filter { port in
                let category = model.ports.category(for: port)
                return !(hideSystem && category == .system) && search.matches(port, category: category, label: model.preferences.label(for: port.port))
            }
            .sorted { (favorites.contains($0.port) ? 0 : 1, $0.port) < (favorites.contains($1.port) ? 0 : 1, $1.port) }
    }

    private var visibleForwards: [PortForwardSession] {
        guard !query.isEmpty else { return model.forwards.sessions }
        return model.forwards.sessions.filter { session in
            let configuration = session.configuration
            return [configuration.name, configuration.namespace, configuration.service, String(configuration.effectivePort)]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func groups(_ ports: [ListeningPort]) -> [(name: String, ports: [ListeningPort])] {
        OrderedDictionary(grouping: ports, by: \.processName).map { ($0.key, $0.value) }
    }
}

struct MenuSectionHeader: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

struct MenuRowBackground: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .environment(\.isRowHovered, hovering)
    }
}

extension EnvironmentValues {
    @Entry var isRowHovered = false
}

struct MenuPortRow: View {
    @Environment(AppModel.self) private var model
    let port: ListeningPort
    var nested = false
    @Binding var confirmingKill: String?

    var body: some View {
        if confirmingKill == port.id {
            HStack(spacing: 8) {
                Text("Kill \(port.processName)?")
                    .lineLimit(1)
                Spacer()
                Button("Cancel") { confirmingKill = nil }
                    .buttonStyle(.glass)
                Button("Kill", role: .destructive) {
                    confirmingKill = nil
                    Task { await model.ports.kill(port) }
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
            }
            .controlSize(.small)
            .modifier(MenuRowBackground())
        } else {
            MenuPortRowContent(port: port, nested: nested, confirmingKill: $confirmingKill)
                .modifier(MenuRowBackground())
                .contextMenu {
                    PortContextMenu(ids: [port.id]) { _ in confirmingKill = port.id }
                }
        }
    }
}

private struct MenuPortRowContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isRowHovered) private var hovered
    let port: ListeningPort
    let nested: Bool
    @Binding var confirmingKill: String?

    var body: some View {
        let category = model.ports.category(for: port)
        let terminating = model.ports.terminating.contains(port.id)
        HStack(spacing: 8) {
            if nested {
                Color.clear.frame(width: 14)
            }
            StatusDot(color: terminating ? .orange : .green, size: 6)
            HStack(spacing: 3) {
                Text(":\(String(port.port))")
                    .font(.body.monospacedDigit().weight(.semibold))
                if model.preferences.favorites.contains(port.port) {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                }
                if model.preferences.isWatching(port.port) {
                    Image(systemName: "eye.fill").font(.caption2).foregroundStyle(.blue)
                }
                if model.tunnels.exposuresByPort[port.port] != nil || model.tunnels.quickTunnel(for: port.port)?.status == .active {
                    Image(systemName: "globe").font(.caption2).foregroundStyle(.orange)
                }
            }
            .frame(width: 92, alignment: .leading)
            if !nested {
                ProcessIcon(process: port.process, category: category, size: 16)
                Text(port.processName)
                    .lineLimit(1)
            } else {
                Text(port.address)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let label = model.preferences.label(for: port.port) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if terminating {
                ProgressView().controlSize(.mini)
            } else if hovered {
                Button("Kill", systemImage: "xmark.circle.fill") {
                    if model.preferences.skipKillConfirmation {
                        Task { await model.ports.kill(port) }
                    } else {
                        confirmingKill = port.id
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Kill \(port.processName)")
            } else {
                Text(verbatim: "\(port.pid)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct MenuProcessGroup: View {
    @Environment(AppModel.self) private var model
    let name: String
    let ports: [ListeningPort]
    @Binding var expanded: Set<String>
    @Binding var confirmingKill: String?

    var body: some View {
        if ports.count == 1, let port = ports.first {
            MenuPortRow(port: port, confirmingKill: $confirmingKill)
        } else {
            let isExpanded = expanded.contains(name)
            let groupID = "group:\(name)"
            VStack(spacing: 0) {
                if confirmingKill == groupID {
                    HStack(spacing: 8) {
                        Text("Kill \(name) on \(ports.count) ports?")
                            .lineLimit(1)
                        Spacer()
                        Button("Cancel") { confirmingKill = nil }
                            .buttonStyle(.glass)
                        Button("Kill", role: .destructive) {
                            confirmingKill = nil
                            Task { await model.ports.kill(ports) }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                    }
                    .controlSize(.small)
                    .modifier(MenuRowBackground())
                } else {
                    GroupHeader(name: name, ports: ports, isExpanded: isExpanded) {
                        withAnimation(.snappy) {
                            if isExpanded { expanded.remove(name) } else { expanded.insert(name) }
                        }
                    } onKill: {
                        if model.preferences.skipKillConfirmation {
                            Task { await model.ports.kill(ports) }
                        } else {
                            confirmingKill = groupID
                        }
                    }
                    .modifier(MenuRowBackground())
                }
                if isExpanded {
                    ForEach(ports) { port in
                        MenuPortRow(port: port, nested: true, confirmingKill: $confirmingKill)
                    }
                }
            }
        }
    }

    private struct GroupHeader: View {
        @Environment(AppModel.self) private var model
        @Environment(\.isRowHovered) private var hovered
        let name: String
        let ports: [ListeningPort]
        let isExpanded: Bool
        let toggle: () -> Void
        let onKill: () -> Void

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14)
                if let first = ports.first {
                    ProcessIcon(process: first.process, category: model.ports.category(for: first), size: 16)
                }
                Text(name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                if hovered {
                    Button("Kill All", systemImage: "xmark.circle.fill", action: onKill)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                } else {
                    Text("\(ports.count) ports")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onTapGesture(perform: toggle)
        }
    }
}

struct MenuForwardRow: View {
    let session: PortForwardSession

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: session.status.tint, size: 6)
            Text(":\(String(session.configuration.effectivePort))")
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.configuration.name)
                    .lineLimit(1)
                Text(session.configuration.namespace)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(session.isActive ? "Stop" : "Start", systemImage: session.isActive ? "stop.fill" : "play.fill") {
                session.isActive ? session.stop() : session.start()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .foregroundStyle(session.isActive ? .red : .green)
        }
        .modifier(MenuRowBackground())
        .contextMenu {
            ForwardActions(session: session)
        }
    }
}

struct MenuQuickTunnelRow: View {
    @Environment(AppModel.self) private var model
    let tunnel: QuickTunnel

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: tunnel.status.tint, size: 6)
            Text(":\(String(tunnel.port))")
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(width: 64, alignment: .leading)
            Text(tunnel.url?.replacingOccurrences(of: "https://", with: "") ?? tunnel.status.title)
                .font(.callout)
                .foregroundStyle(tunnel.url == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            if let url = tunnel.url {
                Button("Copy URL", systemImage: "doc.on.doc") { Pasteboard.copy(url) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Button("Stop", systemImage: "xmark.circle.fill") { model.tunnels.stopQuickTunnel(tunnel) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
        }
        .modifier(MenuRowBackground())
    }
}

struct MenuNamedTunnelRow: View {
    @Environment(AppModel.self) private var model
    let tunnel: NamedTunnel

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: tunnel.tint, size: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(tunnel.name)
                    .lineLimit(1)
                Text(tunnel.status == .running ? "\(tunnel.activeConnections) connections" : tunnel.publicURLs.first ?? tunnel.statusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            switch tunnel.status {
            case .starting, .stopping:
                ProgressView().controlSize(.mini)
            case .running:
                Button("Stop", systemImage: "stop.fill") { model.tunnels.stop(tunnel) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .foregroundStyle(.red)
            case .stopped, .failed:
                Button("Run", systemImage: "play.fill") { model.tunnels.run(tunnel) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .foregroundStyle(.green)
                    .disabled(!model.tunnels.isInstalled)
            }
        }
        .modifier(MenuRowBackground())
    }
}
