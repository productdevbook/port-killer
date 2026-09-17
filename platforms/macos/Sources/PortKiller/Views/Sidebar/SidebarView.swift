import PortKillerKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var searchFocused: Bool
    @State private var browsing = false
    @State private var showingRange = false
    @AppStorage("showTunnelsManagedElsewhere") private var showManagedElsewhere = false

    var body: some View {
        @Bindable var model = model
        @Bindable var ports = model.ports
        let query = ports.filter.searchText.trimmingCharacters(in: .whitespaces)
        let processes = ports.processes(for: model.portScope)
        let inactive = ports.inactivePorts(for: model.portScope)
        let forwards = model.forwards.sessions.filter { $0.matches(query) }
        let quickTunnels = model.tunnels.quickTunnels.filter { $0.matches(query) }
        let namedTunnels = model.tunnels.namedTunnels.filter { tunnel in
            (tunnel.isRunningHere || showManagedElsewhere || tunnel.runSafety != .managedElsewhere) && tunnel.matches(query)
        }
        let pluginSections = model.plugins.itemPlugins.map { plugin in
            (plugin: plugin, items: (model.plugins.items[plugin.id] ?? []).filter { $0.matches(query) })
        }
        let ids = processes.map(\.id)
            + inactive.map { ItemID.inactivePort($0) }
            + forwards.map { ItemID.forward($0.id) }
            + quickTunnels.map { ItemID.quickTunnel($0.id) }
            + namedTunnels.map { ItemID.namedTunnel($0.id) }
            + pluginSections.flatMap { section in section.items.map { ItemID.pluginItem(plugin: section.plugin.id, item: $0.id) } }

        List(selection: $model.selection) {
            if !processes.isEmpty || !inactive.isEmpty {
                Section(model.portScope.sectionTitle) {
                    ForEach(processes) { item in
                        ProcessRow(item: item)
                            .tag(item.id)
                    }
                    ForEach(inactive, id: \.self) { port in
                        ItemRow(title: "Port \(String(port))", subtitle: model.preferences.label(for: port) ?? "Not Running", dimmed: true) {
                            ItemIcon(symbol: "moon.zzz", tint: .secondary)
                        }
                        .tag(ItemID.inactivePort(port))
                    }
                }
            }
            if !forwards.isEmpty {
                Section("Port Forwards") {
                    ForEach(forwards) { session in
                        ForwardRow(session: session)
                            .tag(ItemID.forward(session.id))
                    }
                }
            }
            if !quickTunnels.isEmpty || !namedTunnels.isEmpty {
                Section("Tunnels") {
                    ForEach(quickTunnels) { tunnel in
                        ItemRow(title: tunnel.host ?? "Quick Tunnel", subtitle: "Port \(String(tunnel.port)) · \(tunnel.status.title)") {
                            ItemIcon(symbol: "bolt", tint: tunnel.status == .failed ? .red : .accentColor)
                        }
                        .tag(ItemID.quickTunnel(tunnel.id))
                    }
                    ForEach(namedTunnels) { tunnel in
                        ItemRow(title: tunnel.name, subtitle: tunnel.statusTitle, dimmed: tunnel.runSafety == .managedElsewhere && !tunnel.isRunningHere) {
                            ItemIcon(symbol: "cloud", tint: tunnel.status == .failed ? .red : tunnel.isRunningHere ? .accentColor : .secondary)
                        }
                        .tag(ItemID.namedTunnel(tunnel.id))
                    }
                }
            }
            ForEach(pluginSections, id: \.plugin.id) { section in
                if !section.items.isEmpty {
                    Section(section.plugin.manifest.items?.title ?? section.plugin.manifest.name) {
                        ForEach(section.items) { item in
                            ItemRow(title: item.title, subtitle: item.subtitle ?? item.status.title, badge: item.port.map(String.init)) {
                                ItemIcon(symbol: section.plugin.manifest.icon ?? "puzzlepiece.extension", tint: item.status.iconTint)
                            }
                            .tag(ItemID.pluginItem(plugin: section.plugin.id, item: item.id))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if ids.isEmpty {
                if !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ContentUnavailableView {
                        Label(model.portScope.emptyTitle, systemImage: "network.slash")
                    } description: {
                        Text(model.portScope.emptyMessage)
                    }
                }
            }
        }
        .searchable(text: $ports.filter.searchText, placement: .sidebar, prompt: "Search")
        .searchFocused($searchFocused)
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
        .onChange(of: ids, initial: true) { _, ids in
            if let selection = model.selection, ids.contains(selection) { return }
            model.selection = ids.first
        }
        .contextMenu(forSelectionType: ItemID.self) { selection in
            if let id = selection.first {
                ItemActions(id: id)
            }
        } primaryAction: { selection in
            guard let id = selection.first else { return }
            switch id {
            case .forward(let sessionID):
                model.forwards.sessions.first { $0.id == sessionID }?.toggle()
            case .namedTunnel(let tunnelID):
                guard let tunnel = model.tunnels.namedTunnels.first(where: { $0.id == tunnelID }) else { return }
                tunnel.isRunningHere ? model.tunnels.stop(tunnel) : model.tunnels.run(tunnel)
            default:
                model.inspectorVisible = true
            }
        }
        .onDeleteCommand {
            guard case .process(let pid) = model.selection, let item = model.ports.process(pid: pid) else { return }
            model.ports.requestKill(item.ports)
        }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("New Port Forward", systemImage: "point.3.connected.trianglepath.dotted") {
                        model.addForward(.placeholder())
                    }
                    Button("Browse Cluster…", systemImage: "square.stack.3d.down.forward") { browsing = true }
                        .disabled(model.preferences.locate(.kubectl) == nil)
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuIndicator(.hidden)
                .help("Add a port forward")

                FilterMenu(showManagedElsewhere: $showManagedElsewhere, showingRange: $showingRange)
            }
        }
        .popover(isPresented: $showingRange, arrowEdge: .bottom) {
            PortRangeForm(filter: $ports.filter)
        }
        .sheet(isPresented: $browsing) {
            ServiceBrowser()
        }
        .task(id: model.plugins.itemPlugins.map(\.id)) {
            let store = model.plugins
            await withDiscardingTaskGroup { group in
                for plugin in store.itemPlugins {
                    group.addTask {
                        let interval = max(plugin.manifest.items?.refreshInterval ?? 10, 2)
                        while !Task.isCancelled {
                            await store.refresh(plugin)
                            try? await Task.sleep(for: .seconds(interval))
                        }
                    }
                }
            }
        }
        .task {
            await model.forwards.refreshContext()
        }
        .onAppear { model.tunnels.startDiscovery() }
        .onDisappear { model.tunnels.stopDiscovery() }
    }
}

private struct ProcessRow: View {
    @Environment(AppModel.self) private var model
    let item: ProcessItem

    var body: some View {
        let isTerminating = model.ports.terminating.contains(item.process.pid)
        ItemRow(
            title: item.process.name,
            subtitle: isTerminating ? "Stopping…" : item.label ?? item.category.rawValue,
            badge: item.ports.count == 1 ? item.portList : "\(item.ports[0].port) +\(item.ports.count - 1)",
            isFavorite: item.isFavorite,
            dimmed: isTerminating
        ) {
            ItemIcon(symbol: item.category.symbolName, process: item.process)
        }
    }
}

private struct ForwardRow: View {
    let session: PortForwardSession

    var body: some View {
        let configuration = session.configuration
        ItemRow(
            title: configuration.name,
            subtitle: configuration.isEnabled || session.isActive ? session.status.title : "Disabled",
            badge: String(configuration.effectivePort),
            dimmed: !configuration.isEnabled && !session.isActive
        ) {
            ItemIcon(symbol: "point.3.connected.trianglepath.dotted", tint: session.status == .failed ? .red : session.isActive ? .accentColor : .secondary)
        }
    }
}

private struct FilterMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var showManagedElsewhere: Bool
    @Binding var showingRange: Bool

    var body: some View {
        @Bindable var model = model
        @Bindable var ports = model.ports
        @Bindable var preferences = model.preferences
        let isFiltering = model.portScope != .all || ports.filter.isActive || preferences.hideSystemProcesses
        Menu {
            Picker("Show", selection: $model.portScope) {
                ForEach(PortScope.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Toggle("Hide System Processes", isOn: $preferences.hideSystemProcesses)
            Toggle("Show Tunnels Managed Elsewhere", isOn: $showManagedElsewhere)
            Menu("Categories") {
                ForEach(ProcessCategory.allCases) { category in
                    Toggle(category.rawValue, isOn: $ports.filter.categories.contains(category))
                }
            }
            Button("Port Range…") { showingRange = true }
            Divider()
            Button("Reset Filters") {
                ports.filter.reset()
                model.portScope = .all
            }
            .disabled(!ports.filter.isActive && model.portScope == .all)
        } label: {
            Label("Filter", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .menuIndicator(.hidden)
        .help("Filter ports")
    }
}

private struct PortRangeForm: View {
    @Binding var filter: PortFilter

    var body: some View {
        Form {
            TextField("From", value: $filter.minPort, format: .number.grouping(.never), prompt: Text("1"))
            TextField("To", value: $filter.maxPort, format: .number.grouping(.never), prompt: Text("65535"))
            TrailingButtons {
                Button("Clear Range") {
                    filter.minPort = nil
                    filter.maxPort = nil
                }
                .disabled(!filter.hasRange)
            }
        }
        .formStyle(.grouped)
        .frame(width: 240)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension PortForwardSession {
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [configuration.name, configuration.namespace, configuration.service, String(configuration.effectivePort)]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private extension QuickTunnel {
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [host ?? "", String(port)].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private extension NamedTunnel {
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return ([name] + publicURLs).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private extension PluginItem {
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [title, subtitle ?? "", port.map(String.init) ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
