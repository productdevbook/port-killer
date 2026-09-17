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
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(260)
        } detail: {
            CanvasView()
        }
        .inspector(isPresented: $model.inspectorVisible) {
            InspectorView(tab: model.inspectorTab)
                .frame(width: 300)
                .inspectorColumnWidth(300)
                .toolbar {
                    ToolbarSpacer(.flexible)
                    InspectorTabButtons(tab: $model.inspectorTab, visible: $model.inspectorVisible)
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
        .background {
            Color.clear
                .alert(error: $plugins.error) { _ in
                    Button("OK", role: .cancel) {}
                } message: { error in
                    Text(error.message)
                }
        }
        .background {
            Color.clear
                .sheet(item: $plugins.pendingRun) { request in
                    PluginRunSheet(request: request)
                }
        }
        .background {
            Color.clear
                .sheet(item: $plugins.presentedRun) { run in
                    PluginRunDetails(run: run)
                }
        }
        .background {
            Color.clear
                .alert(
                    "Install “\(plugins.pendingInstall?.plugin.manifest.name ?? "Plugin")”?",
                    isPresented: Binding(get: { plugins.pendingInstall != nil }, set: { if !$0 { plugins.pendingInstall = nil } }),
                    presenting: plugins.pendingInstall
                ) { request in
                    Button("Install and Turn On") { plugins.install(from: request.source, enable: true) }
                    Button("Install") { plugins.install(from: request.source, enable: false) }
                    Button("Cancel", role: .cancel) {}
                } message: { request in
                    Text([request.plugin.manifest.summary, "Plugins run with your user account. Install only plugins you trust."].compactMap { $0 }.joined(separator: "\n\n"))
                }
        }
        .confirmationDialog(killTitle, isPresented: Binding(get: { !ports.pendingKill.isEmpty }, set: { if !$0 { ports.pendingKill = [] } }), presenting: ports.pendingKill) { targets in
            Button("Kill", role: .destructive) { kill(targets, .graceful) }
            Button("Force Kill") { kill(targets, .force) }
            Button("Kill Process Tree") { kill(targets, .tree) }
            Button("Kill and Close Connections") { kill(targets, .deep) }
        } message: { targets in
            Text(killMessage(targets))
        }
        .onAppear {
            model.openWindow = openWindow
        }
    }

    private var killTitle: String {
        guard let first = model.ports.pendingKill.first else { return "" }
        let ports = model.ports.pendingKill.map { String($0.port) }.joined(separator: ", ")
        return "Kill \(first.processName) on Port \(ports)?"
    }

    private func killMessage(_ targets: [ListeningPort]) -> String {
        let pids = Set(targets.map(\.pid))
        let others = model.ports.ports.filter { pids.contains($0.pid) && !targets.contains($0) }.map { String($0.port) }
        let explanation = "PortKiller asks the process to quit, then stops it if it doesn't within a moment."
        guard !others.isEmpty else { return explanation }
        return "\(others.count == 1 ? "Port" : "Ports") \(others.joined(separator: ", ")) will close too, because they belong to the same process. \(explanation)"
    }

    private func kill(_ targets: [ListeningPort], _ mode: KillMode) {
        model.ports.pendingKill = []
        Task { await model.ports.kill(targets, mode: mode) }
    }
}

struct InspectorTabButtons: ToolbarContent {
    @Binding var tab: InspectorTab
    @Binding var visible: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup {
            ForEach(InspectorTab.allCases) { item in
                Toggle(isOn: Binding(
                    get: { visible && tab == item },
                    set: { isOn in
                        if isOn {
                            tab = item
                            visible = true
                        } else {
                            visible = false
                        }
                    }
                )) {
                    Label(item.title, systemImage: item.symbol)
                }
                .help(item.title)
            }
        }
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
        CommandGroup(after: .textEditing) {
            Button("Find") {
                model.show()
                model.searchFocusRequest += 1
            }
            .keyboardShortcut("f")
        }
        CommandGroup(before: .toolbar) {
            Button("Refresh Ports") {
                Task { await model.ports.refresh() }
            }
            .keyboardShortcut("r")
            Divider()
            ForEach(Array(InspectorTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) {
                    model.inspectorTab = tab
                    model.inspectorVisible = true
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
            }
            Button(model.inspectorVisible ? "Hide Inspector" : "Show Inspector") { model.inspectorVisible.toggle() }
                .keyboardShortcut("i")
            Divider()
            ForEach(GraphZoomRequest.Kind.allCases.reversed(), id: \.self) { kind in
                Button(kind.title) { model.graphZoomRequest = GraphZoomRequest(kind: kind) }
                    .keyboardShortcut(kind.shortcut)
            }
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
