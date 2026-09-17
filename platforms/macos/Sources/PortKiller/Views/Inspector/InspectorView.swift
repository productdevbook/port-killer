import PortKillerKit
import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    let tab: InspectorTab

    var body: some View {
        Group {
            switch model.selection {
            case .process(let pid):
                if let item = model.ports.process(pid: pid) {
                    switch tab {
                    case .settings: ProcessSettingsInspector(item: item)
                    case .logs: unavailable("No Logs", "Ports don't keep logs. Port forwards and tunnels do.")
                    case .info: ProcessInfoInspector(item: item)
                    case .sharing: ProcessSharingInspector(item: item)
                    case .plugins: ProcessPluginsInspector(item: item)
                    }
                } else {
                    noSelection
                }
            case .inactivePort(let port):
                switch tab {
                case .settings: InactivePortInspector(port: port)
                default: unavailable("Not Running", "Nothing listens on port \(port) right now.")
                }
            case .forward(let id):
                if let session = model.forwards.sessions.first(where: { $0.id == id }) {
                    switch tab {
                    case .settings: ForwardSettingsInspector(session: session).id(id)
                    case .logs: ForwardLogsInspector(session: session)
                    case .info: ForwardInfoInspector(session: session)
                    case .sharing: unavailable("No Sharing", "Port forwards connect a cluster service to this Mac.")
                    case .plugins: unavailable("No Plugin Actions", "Plugins add actions to ports.")
                    }
                } else {
                    noSelection
                }
            case .quickTunnel(let id):
                if let tunnel = model.tunnels.quickTunnels.first(where: { $0.id == id }) {
                    switch tab {
                    case .logs: LogConsole(lines: tunnel.logs.map(\.consoleLine), emptyText: "cloudflared output appears here.", onClear: { tunnel.clearLogs() })
                    case .info: QuickTunnelInfoInspector(tunnel: tunnel)
                    default: unavailable("Nothing to Change", "Quick tunnels have no settings. Stop it and share the port again to change it.")
                    }
                } else {
                    noSelection
                }
            case .namedTunnel(let id):
                if let tunnel = model.tunnels.namedTunnels.first(where: { $0.id == id }) {
                    switch tab {
                    case .logs: LogConsole(lines: tunnel.logs.map(\.consoleLine), emptyText: "Run the tunnel to see cloudflared output.", onClear: { tunnel.clearLogs() })
                    case .info: NamedTunnelInfoInspector(tunnel: tunnel)
                    default: unavailable("Nothing to Change", "Named tunnels are configured with cloudflared and the Cloudflare dashboard.")
                    }
                } else {
                    noSelection
                }
            case .pluginItem(let pluginID, let itemID):
                if let plugin = model.plugins.itemPlugins.first(where: { $0.id == pluginID }),
                   let item = model.plugins.items[pluginID]?.first(where: { $0.id == itemID }) {
                    switch tab {
                    case .info: PluginItemInfoInspector(plugin: plugin, item: item)
                    case .plugins: PluginItemActionsInspector(plugin: plugin, item: item)
                    default: unavailable("Not Available", "\(plugin.manifest.name) provides info and actions for this item.")
                    }
                } else {
                    noSelection
                }
            case .overview, nil:
                noSelection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSelection: some View {
        unavailable("No Selection", "Select a port, port forward or tunnel to inspect it.")
    }

    private func unavailable(_ title: String, _ message: String) -> some View {
        ContentUnavailableView(title, systemImage: tab.symbol, description: Text(message))
    }
}
