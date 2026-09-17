import AppKit
import PortKillerKit
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        @Bindable var ports = model.ports
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 300)
        } detail: {
            detail
        }
        .inspector(isPresented: $model.inspectorVisible) {
            inspector
                .inspectorColumnWidth(min: 290, ideal: 330, max: 440)
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem {
                        Toggle(isOn: $model.inspectorVisible) {
                            Label("Inspector", systemImage: "sidebar.trailing")
                        }
                        .help("Show or hide the inspector")
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
        .onAppear {
            model.openWindow = openWindow
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebar {
        case .portForwards:
            ForwardsView()
        case .tunnels:
            TunnelsView()
        case .sponsors:
            SponsorsView()
        default:
            PortsView(item: model.sidebar)
                .id(model.sidebar)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        switch model.sidebar {
        case .portForwards:
            ForwardInspector()
        case .tunnels:
            TunnelInspector()
        case .sponsors:
            ContentUnavailableView("Thank You", systemImage: "heart", description: Text("Sponsors keep PortKiller free and open source."))
        default:
            PortInspector()
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let categoryCounts = model.ports.categoryCounts
        List(selection: Binding(get: { model.sidebar }, set: { if let item = $0 { model.sidebar = item } })) {
            Section("Ports") {
                row(.allPorts, count: model.ports.ports.count)
                row(.favorites, count: model.preferences.favorites.count, tint: .yellow)
                row(.watched, count: model.preferences.watchedPorts.count, tint: .blue)
            }

            Section("Networking") {
                row(.portForwards, count: model.forwards.sessions.count, tint: .indigo, active: model.forwards.connectedCount > 0)
                row(.tunnels, count: model.tunnels.quickTunnels.count + model.tunnels.namedTunnels.count, tint: .orange, active: model.tunnels.activeCount > 0)
            }

            Section("Categories") {
                ForEach(ProcessCategory.allCases) { category in
                    row(.category(category), count: categoryCounts[category, default: 0], tint: category.tint)
                }
            }

            Section {
                row(.sponsors, count: nil, tint: .pink)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ item: SidebarItem, count: Int?, tint: Color? = nil, active: Bool = false) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer()
                if active {
                    StatusDot(color: .green, size: 6)
                }
            }
        } icon: {
            Image(systemName: item.symbolName)
                .foregroundStyle(tint ?? .accentColor)
        }
        .badge(count ?? 0)
        .tag(item)
    }
}

struct PortKillerCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { model.updater.checkForUpdates() }
                .disabled(!model.updater.canCheckForUpdates)
        }
        CommandGroup(before: .toolbar) {
            Button("Refresh Ports") {
                Task { await model.ports.refresh() }
            }
            .keyboardShortcut("r")
            Toggle("Group Ports by Process", isOn: Bindable(model.preferences).useTreeView)
                .keyboardShortcut("t")
            Divider()
            Button("Show All Ports") { model.show(.allPorts) }
                .keyboardShortcut("1")
            Button("Show Port Forwards") { model.show(.portForwards) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Show Cloudflare Tunnels") { model.show(.tunnels) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("PortKiller on GitHub") { open(AppInfo.repository) }
            Button("Report an Issue") { open(AppInfo.issues) }
            Button("Sponsor PortKiller") { open(AppInfo.sponsors) }
        }
    }

    private func open(_ url: URL?) {
        if let url { NSWorkspace.shared.open(url) }
    }
}
