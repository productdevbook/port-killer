import SwiftUI
import AppKit

struct PortForwarderWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var discoveryManager: KubernetesDiscoveryManager?

    var body: some View {
        TabView {
            ConnectionsTab(discoveryManager: $discoveryManager)
                .tabItem {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }

            ServiceBrowserTab()
                .tabItem {
                    Label("Browse", systemImage: "magnifyingglass")
                }

            PortForwarderSettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .frame(minWidth: 850, idealWidth: 1000, minHeight: 600, idealHeight: 700)
        .sheet(item: $discoveryManager) { dm in
            ServiceBrowserView(
                discoveryManager: dm,
                onServiceSelected: { config in
                    appState.portForwardManager.addConnection(config)
                    discoveryManager = nil
                },
                onCancel: {
                    discoveryManager = nil
                }
            )
        }
    }
}
