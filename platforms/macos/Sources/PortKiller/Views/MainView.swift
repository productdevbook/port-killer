import AppKit
import PortKillerKit
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        @Bindable var ports = model.ports
        @Bindable var plugins = model.plugins
        content
            .alert(error: $plugins.error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.message)
            }
            .searchable(text: $ports.filter.searchText, placement: .toolbar, prompt: searchPrompt)
            .navigationTitle("PortKiller")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $model.tab) {
                        Text("Ports").tag(AppTab.ports)
                        Text("Port Forwards").tag(AppTab.forwards)
                        Text("Tunnels").tag(AppTab.tunnels)
                        ForEach(plugins.tabPlugins) { plugin in
                            Text(plugin.manifest.items?.title ?? plugin.manifest.name).tag(AppTab.plugin(plugin.id))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .inspector(isPresented: $model.inspectorVisible) {
                inspector
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 440)
                    .toolbar {
                        ToolbarSpacer(.flexible)
                        ToolbarItem {
                            Toggle(isOn: $model.inspectorVisible) {
                                Label("Info", systemImage: "info.circle")
                            }
                            .help("Show or hide details")
                        }
                    }
            }
            .sheet(isPresented: $model.showingOnboarding) {
                OnboardingView()
                    .interactiveDismissDisabled()
            }
            .alert(error: $ports.error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.message)
            }
            .confirmationDialog(killTitle, isPresented: Binding(get: { !ports.pendingKill.isEmpty }, set: { if !$0 { ports.pendingKill = [] } }), presenting: ports.pendingKill) { targets in
                Button("Kill", role: .destructive) { kill(targets, .graceful) }
                Button("Force Kill") { kill(targets, .force) }
                Button("Kill Process Tree") { kill(targets, .tree) }
                Button("Kill and Close Connections") { kill(targets, .deep) }
            } message: { targets in
                Text(targets.count == 1 ? "PortKiller asks the process to quit, then stops it if it doesn't within a moment." : "PortKiller stops \(targets.count) processes.")
            }
            .onChange(of: plugins.tabPlugins.map(\.id)) { _, ids in
                if case .plugin(let id) = model.tab, !ids.contains(id) { model.tab = .ports }
            }
            .onAppear {
                model.openWindow = openWindow
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .ports:
            PortsView()
        case .forwards:
            ForwardsView()
        case .tunnels:
            TunnelsView()
        case .plugin(let id):
            if let plugin = model.plugins.tabPlugins.first(where: { $0.id == id }) {
                PluginView(plugin: plugin)
                    .id(id)
            } else {
                PortsView()
            }
        }
    }

    @ViewBuilder
    private var inspector: some View {
        switch model.tab {
        case .ports:
            PortInspector()
        case .forwards:
            ForwardInspector()
        case .tunnels:
            TunnelInspector()
        case .plugin(let id):
            if let plugin = model.plugins.tabPlugins.first(where: { $0.id == id }) {
                PluginInspector(plugin: plugin)
            }
        }
    }

    private var searchPrompt: String {
        switch model.tab {
        case .ports: "Port, process, PID or command"
        case .forwards: "Name, namespace or service"
        case .tunnels: "Tunnel, address or port"
        case .plugin: "Search"
        }
    }

    private var killTitle: String {
        let pendingKill = model.ports.pendingKill
        guard pendingKill.count == 1, let port = pendingKill.first else { return "Kill \(pendingKill.count) Processes?" }
        return "Kill \(port.processName) on Port \(port.port)?"
    }

    private func kill(_ targets: [ListeningPort], _ mode: KillMode) {
        model.ports.pendingKill = []
        Task { await model.ports.kill(targets, mode: mode) }
    }
}

struct PortKillerCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Port Forward") {
                model.addForward(.placeholder())
                model.show()
            }
            .keyboardShortcut("n")
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { model.updater.checkForUpdates() }
                .disabled(!model.updater.canCheckForUpdates)
        }
        CommandGroup(before: .toolbar) {
            Button("Ports") { model.tab = .ports }
                .keyboardShortcut("1")
            Button("Port Forwards") { model.tab = .forwards }
                .keyboardShortcut("2")
            Button("Tunnels") { model.tab = .tunnels }
                .keyboardShortcut("3")
            Divider()
            Button("Refresh Ports") {
                Task { await model.ports.refresh() }
            }
            .keyboardShortcut("r")
            Toggle("Group Ports by Process", isOn: Bindable(model.preferences).useTreeView)
                .keyboardShortcut("t")
            Button(model.inspectorVisible ? "Hide Details" : "Show Details") { model.inspectorVisible.toggle() }
                .keyboardShortcut("i")
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("PortKiller on GitHub") { open(AppInfo.repository) }
            Button("Build a Plugin") { open(AppInfo.pluginGuide) }
            Button("Report an Issue") { open(AppInfo.issues) }
            Divider()
            Button("Sponsors") { model.showSponsors() }
            Button("Sponsor PortKiller") { open(AppInfo.sponsors) }
        }
    }

    private func open(_ url: URL?) {
        if let url { NSWorkspace.shared.open(url) }
    }
}
