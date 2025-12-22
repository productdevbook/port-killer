import SwiftUI

struct PortForwarderToolbar: View {
    @Environment(AppState.self) private var appState
    @Binding var searchText: String
    @Binding var groupByNamespace: Bool
    @Binding var showServiceBrowser: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 200)

            // Group toggle
            Button {
                groupByNamespace.toggle()
            } label: {
                Image(systemName: groupByNamespace ? "folder.fill" : "list.bullet")
            }
            .buttonStyle(.bordered)
            .help(groupByNamespace ? "Show flat list" : "Group by namespace")

            Spacer()

            let manager = appState.portForwardManager

            if !manager.connections.isEmpty {
                Button {
                    manager.startAll()
                } label: {
                    Label("Start All", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(manager.allConnected)

                Button {
                    manager.stopAll()
                } label: {
                    Label("Stop All", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(manager.connectedCount == 0)
            }

            Button {
                let config = PortForwardConnectionConfig(
                    name: "New Connection",
                    namespace: "default",
                    service: "service-name",
                    localPort: 8080,
                    remotePort: 80
                )
                appState.portForwardManager.addConnection(config)
            } label: {
                Label("Add", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.bordered)

            Button {
                Task { appState.kubernetesDiscoveryManager.loadNamespaces() }
                showServiceBrowser = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!appState.scanner.isKubectlAvailable())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
