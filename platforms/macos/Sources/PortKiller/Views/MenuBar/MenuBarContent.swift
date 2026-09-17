import AppKit
import OrderedCollections
import PortKillerKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var confirmingKill: MenuKillTarget?
    @State private var confirmingKillAll = false
    @State private var expanded: Set<String> = []

    var body: some View {
        let ports = visiblePorts
        let sharedPorts = model.tunnels.sharedPorts
        let forwards = visibleForwards
        let quick = model.tunnels.quickTunnels
        let named = model.tunnels.namedTunnels.filter { $0.isRunningHere || $0.runSafety == .safe }
        VStack(spacing: 0) {
            searchField(count: ports.count)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if ports.isEmpty, forwards.isEmpty, quick.isEmpty, named.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "No Listening Ports" : "No Results", systemImage: "network.slash")
                            .padding(.vertical, 60)
                    }
                    if !ports.isEmpty {
                        MenuSectionHeader(title: "Ports")
                        if model.preferences.useTreeView {
                            ForEach(groups(ports), id: \.name) { group in
                                MenuProcessGroup(name: group.name, ports: group.ports, sharedPorts: sharedPorts, expanded: $expanded, confirmingKill: $confirmingKill)
                            }
                        } else {
                            ForEach(ports) { port in
                                MenuPortRow(port: port, isShared: sharedPorts.contains(port.port), confirmingKill: $confirmingKill)
                            }
                        }
                    }
                    if !forwards.isEmpty {
                        MenuSectionHeader(title: "Port Forwards")
                        ForEach(forwards) { MenuForwardRow(session: $0) }
                    }
                    if !quick.isEmpty {
                        MenuSectionHeader(title: "Quick Tunnels")
                        ForEach(quick) { MenuQuickTunnelRow(tunnel: $0) }
                    }
                    if !named.isEmpty {
                        MenuSectionHeader(title: "Tunnels")
                        ForEach(named) { MenuNamedTunnelRow(tunnel: $0) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .frame(height: 420)
            footer(ports)
        }
        .frame(width: 380)
        .task {
            await model.ports.refresh()
            model.tunnels.discoverIfNeeded()
        }
    }

    private func searchField(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            Text("\(count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.fill.tertiary, in: .capsule)
        .padding(10)
    }

    @ViewBuilder
    private func footer(_ ports: [ListeningPort]) -> some View {
        if confirmingKillAll {
            HStack(spacing: 8) {
                Text("Kill \(ports.count) processes?")
                Spacer()
                Button("Cancel") { confirmingKillAll = false }
                Button("Kill All", role: .destructive) {
                    confirmingKillAll = false
                    Task { await model.ports.kill(ports) }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        } else {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        MenuControlButton(title: "Refresh", symbol: "arrow.clockwise", key: "r") {
                            Task { await model.ports.refresh() }
                        }
                        MenuControlButton(
                            title: model.preferences.useTreeView ? "Show as List" : "Group by Process",
                            symbol: model.preferences.useTreeView ? "list.bullet" : "list.bullet.indent",
                            key: "t"
                        ) {
                            model.preferences.useTreeView.toggle()
                        }
                        MenuControlButton(title: "Kill All", symbol: "xmark.octagon", key: "k", tint: .red) {
                            if model.preferences.skipKillConfirmation {
                                Task { await model.ports.kill(ports) }
                            } else {
                                confirmingKillAll = true
                            }
                        }
                        .disabled(ports.isEmpty)
                    }
                    .padding(.horizontal, 4)
                    .glassEffect(.regular.interactive(), in: .capsule)

                    Spacer()

                    HStack(spacing: 0) {
                        MenuControlButton(title: "Open PortKiller", symbol: "macwindow", key: "o") {
                            model.show()
                        }
                        MenuControlButton(title: "Settings", symbol: "gearshape", key: ",") {
                            NSApp.activate()
                            openSettings()
                        }
                        MenuControlButton(title: "Quit PortKiller", symbol: "power", key: "q") {
                            NSApp.terminate(nil)
                        }
                    }
                    .padding(.horizontal, 4)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .padding(10)
        }
    }

    private var visiblePorts: [ListeningPort] {
        let favorites = model.preferences.favorites
        return model.ports.listeners(for: .all, filter: PortFilter(searchText: query))
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

private enum MenuKillTarget: Hashable {
    case port(ListeningPort.ID)
    case group(String)
}

private struct MenuControlButton: View {
    let title: String
    let symbol: String
    let key: KeyEquivalent
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(tint ?? .primary)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct MenuSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 3)
    }
}

private struct MenuRowBackground: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(hovering ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6, style: .continuous))
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .environment(\.isRowHovered, hovering)
    }
}

private extension EnvironmentValues {
    @Entry var isRowHovered = false
}

private struct RowActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(title)
    }
}

private struct MenuKillConfirmRow: View {
    let title: String
    @Binding var confirmingKill: MenuKillTarget?
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
            Spacer()
            Button("Cancel") { confirmingKill = nil }
            Button("Kill", role: .destructive) {
                confirmingKill = nil
                onKill()
            }
        }
        .controlSize(.small)
        .modifier(MenuRowBackground())
    }
}

private struct MenuPortRow: View {
    @Environment(AppModel.self) private var model
    let port: ListeningPort
    var nested = false
    let isShared: Bool
    @Binding var confirmingKill: MenuKillTarget?

    var body: some View {
        let id = MenuKillTarget.port(port.id)
        if confirmingKill == id {
            MenuKillConfirmRow(title: "Kill \(port.processName)?", confirmingKill: $confirmingKill) {
                Task { await model.ports.kill([port]) }
            }
        } else {
            MenuPortRowContent(port: port, nested: nested, isShared: isShared, confirmingKill: $confirmingKill)
                .modifier(MenuRowBackground())
                .contextMenu {
                    ProcessActions(ports: [port]) { confirmingKill = id }
                }
        }
    }
}

private struct MenuPortRowContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isRowHovered) private var hovered
    let port: ListeningPort
    let nested: Bool
    let isShared: Bool
    @Binding var confirmingKill: MenuKillTarget?

    var body: some View {
        let preferences = model.preferences
        let terminating = model.ports.terminating.contains(port.pid)
        HStack(spacing: 8) {
            if nested {
                Color.clear.frame(width: 18)
                Text(port.address)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ProcessIcon(process: port.process, category: model.ports.category(for: port))
                Text(port.processName)
                    .lineLimit(1)
            }
            Group {
                if preferences.favorites.contains(port.port) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
                if preferences.isWatching(port.port) {
                    Image(systemName: "eye.fill").foregroundStyle(.secondary)
                }
                if isShared {
                    Image(systemName: "globe").foregroundStyle(.orange)
                }
            }
            .font(.caption2)
            if let label = preferences.label(for: port.port) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if terminating {
                ProgressView().controlSize(.mini)
            } else if hovered {
                RowActionButton(title: "Kill \(port.processName)", symbol: "xmark.circle.fill") {
                    if preferences.skipKillConfirmation {
                        Task { await model.ports.kill([port]) }
                    } else {
                        confirmingKill = .port(port.id)
                    }
                }
            }
            Text(verbatim: ":\(port.port)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct MenuProcessGroup: View {
    @Environment(AppModel.self) private var model
    let name: String
    let ports: [ListeningPort]
    let sharedPorts: Set<Int>
    @Binding var expanded: Set<String>
    @Binding var confirmingKill: MenuKillTarget?

    var body: some View {
        if ports.count == 1, let port = ports.first {
            MenuPortRow(port: port, isShared: sharedPorts.contains(port.port), confirmingKill: $confirmingKill)
        } else {
            let isExpanded = expanded.contains(name)
            let groupID = MenuKillTarget.group(name)
            VStack(spacing: 0) {
                if confirmingKill == groupID {
                    MenuKillConfirmRow(title: "Kill \(name) on \(ports.count) ports?", confirmingKill: $confirmingKill) {
                        Task { await model.ports.kill(ports) }
                    }
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
                        MenuPortRow(port: port, nested: true, isShared: sharedPorts.contains(port.port), confirmingKill: $confirmingKill)
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
                if let first = ports.first {
                    ProcessIcon(process: first.process, category: model.ports.category(for: first))
                }
                Text(name)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Spacer(minLength: 6)
                if hovered {
                    RowActionButton(title: "Kill All", symbol: "xmark.circle.fill", action: onKill)
                }
                Text("\(ports.count) ports")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
            .onTapGesture(perform: toggle)
        }
    }
}

private struct MenuForwardRow: View {
    @Environment(\.isRowHovered) private var hovered
    let session: PortForwardSession

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: session.status.tint)
                .frame(width: 18)
            Text(session.configuration.name)
                .lineLimit(1)
            Spacer(minLength: 6)
            if hovered {
                RowActionButton(title: session.isActive ? "Stop" : "Start", symbol: session.isActive ? "stop.fill" : "play.fill") {
                    session.toggle()
                }
            }
            Text(verbatim: ":\(session.configuration.effectivePort)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .modifier(MenuRowBackground())
        .contextMenu {
            ForwardActions(session: session)
        }
    }
}

private struct MenuQuickTunnelRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isRowHovered) private var hovered
    let tunnel: QuickTunnel

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: tunnel.status.tint)
                .frame(width: 18)
            Text(tunnel.host ?? tunnel.status.title)
                .foregroundStyle(tunnel.url == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if hovered {
                if let url = tunnel.url {
                    RowActionButton(title: "Copy URL", symbol: "doc.on.doc") { Pasteboard.copy(url.absoluteString) }
                }
                RowActionButton(title: "Stop", symbol: "xmark.circle.fill") { model.tunnels.stopQuickTunnel(tunnel) }
            }
            Text(verbatim: ":\(tunnel.port)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .modifier(MenuRowBackground())
    }
}

private struct MenuNamedTunnelRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isRowHovered) private var hovered
    let tunnel: NamedTunnel

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: tunnel.tint)
                .frame(width: 18)
            Text(tunnel.name)
                .lineLimit(1)
            Spacer(minLength: 6)
            switch tunnel.status {
            case .starting, .stopping:
                ProgressView().controlSize(.mini)
            case .running:
                if hovered {
                    RowActionButton(title: "Stop", symbol: "stop.fill") { model.tunnels.stop(tunnel) }
                }
            case .stopped, .failed:
                if hovered, model.tunnels.isInstalled {
                    RowActionButton(title: "Run", symbol: "play.fill") { model.tunnels.run(tunnel) }
                }
            }
            Text(tunnel.status == .running ? "\(tunnel.activeConnections) conn" : tunnel.statusTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .modifier(MenuRowBackground())
    }
}
