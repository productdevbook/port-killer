import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(SponsorManager.self) private var sponsorManager
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showKillAllConfirmation = false

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } content: {
            contentView
                .searchable(text: $state.filter.searchText, prompt: "Search ports, processes...")
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            toolbarContent
        }
        .onAppear {
            // Ensure app is properly activated for keyboard input
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .confirmationDialog(
            "Kill All Processes",
            isPresented: $showKillAllConfirmation
        ) {
            Button("Kill All (\(appState.filteredPorts.count) processes)", role: .destructive) {
                Task {
                    await appState.killAll()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to kill all \(appState.filteredPorts.count) processes? This action cannot be undone.")
        }
        .onKeyPress(.delete) {
            if let port = appState.selectedPort {
                Task {
                    await appState.killPort(port)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.deleteForward) {
            if let port = appState.selectedPort {
                Task {
                    await appState.killPort(port)
                }
                return .handled
            }
            return .ignored
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch appState.selectedSidebarItem {
        case .settings:
            SettingsView(state: appState, updateManager: appState.updateManager)
                .id("settings")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: .infinity)
        case .sponsors:
            SponsorsPageView(sponsorManager: sponsorManager)
                .id("sponsors")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: .infinity)
        default:
            VStack(spacing: 0) {
                PortTableView()

                // Status bar
                statusBar
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if appState.selectedSidebarItem == .settings || appState.selectedSidebarItem == .sponsors {
            EmptyView()
        } else if let selectedPort = appState.selectedPort {
            PortDetailView(port: selectedPort)
        } else {
            ContentUnavailableView {
                Label("No Port Selected", systemImage: "network.slash")
            } description: {
                Text("Select a port from the list to view details")
            }
        }
    }

    private var statusBar: some View {
        HStack {
            // Port count
            Group {
                if appState.filter.isActive || appState.selectedSidebarItem != .allPorts {
                    Text("\(appState.filteredPorts.count) of \(appState.ports.count) ports")
                } else {
                    Text("\(appState.ports.count) ports listening")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            // Scanning indicator
            if appState.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task {
                    await appState.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appState.isScanning)
            .help("Refresh port list (Cmd+R)")

            Button {
                appState.selectedSidebarItem = .settings
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Open Settings (Cmd+,)")
        }
    }
}
