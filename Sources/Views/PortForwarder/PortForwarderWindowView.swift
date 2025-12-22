import SwiftUI
import AppKit

struct PortForwarderWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var showServiceBrowser = false

    var body: some View {
        TabView {
            ConnectionsTab(showServiceBrowser: $showServiceBrowser)
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
        .sheet(isPresented: $showServiceBrowser) {
            ServiceBrowserView(
                discoveryManager: appState.kubernetesDiscoveryManager,
                onServiceSelected: { config in
                    appState.portForwardManager.addConnection(config)
                    showServiceBrowser = false
                },
                onCancel: {
                    showServiceBrowser = false
                }
            )
        }
    }
}
