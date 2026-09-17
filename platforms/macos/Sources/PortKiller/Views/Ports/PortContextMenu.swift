import AppKit
import PortKillerKit
import SwiftUI

struct PortContextMenu: View {
    @Environment(AppModel.self) private var model
    let ids: Set<PortRow.ID>
    let onKill: ([ListeningPort]) -> Void

    var body: some View {
        let listeners = model.ports.listeners(ids: ids)
        let inactivePorts = ids.compactMap { id in id.hasPrefix("inactive:") ? Int(id.dropFirst("inactive:".count)) : nil }

        if listeners.count == 1, let port = listeners.first {
            single(port)
        } else if !listeners.isEmpty {
            Button("Kill \(listeners.count) Processes…", role: .destructive) { onKill(listeners) }
        }

        if !inactivePorts.isEmpty {
            if !listeners.isEmpty { Divider() }
            Button(inactivePorts.count == 1 ? "Remove Port \(inactivePorts[0])" : "Remove \(inactivePorts.count) Ports") {
                inactivePorts.forEach(model.ports.removeInactive)
            }
        }
    }

    @ViewBuilder
    private func single(_ port: ListeningPort) -> some View {
        let preferences = model.preferences
        if let url = port.localURL {
            Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(url) }
            Button("Copy URL", systemImage: "link") { Pasteboard.copy(url.absoluteString) }
        }
        Menu("Copy") {
            Button("Port Number") { Pasteboard.copy(String(port.port)) }
            Button("Process ID") { Pasteboard.copy(String(port.pid)) }
            Button("Command") { Pasteboard.copy(port.process.command) }
            if let path = port.process.executablePath {
                Button("Executable Path") { Pasteboard.copy(path) }
            }
        }

        Divider()

        Button(preferences.favorites.contains(port.port) ? "Remove from Favorites" : "Add to Favorites", systemImage: "star") {
            preferences.toggleFavorite(port.port)
        }
        Button(preferences.isWatching(port.port) ? "Stop Watching" : "Watch Port", systemImage: "eye") {
            preferences.toggleWatch(port.port)
        }
        Menu("Category") {
            let current = model.ports.category(for: port)
            ForEach(ProcessCategory.allCases) { category in
                Toggle(category.rawValue, isOn: Binding(
                    get: { current == category },
                    set: { _ in preferences.setCategoryOverride(category, for: port.processName) }
                ))
            }
            if preferences.categoryOverride(for: port.processName) != nil {
                Divider()
                Button("Detect Automatically") { preferences.setCategoryOverride(nil, for: port.processName) }
            }
        }
        Button("Edit Label and Note…", systemImage: "pencil") {
            model.ports.selection = [port.id]
            model.inspectorVisible = true
        }

        Divider()

        tunnelActions(port)

        Divider()

        if let path = port.process.executablePath {
            Button("Show Executable in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
            }
        }
        Button("Kill \(port.processName)…", systemImage: "xmark.octagon", role: .destructive) {
            onKill([port])
        }
    }

    @ViewBuilder
    private func tunnelActions(_ port: ListeningPort) -> some View {
        let tunnels = model.tunnels
        if let tunnel = tunnels.quickTunnel(for: port.port), tunnel.status != .failed {
            if let url = tunnel.url {
                Button("Copy Tunnel URL", systemImage: "cloud") { Pasteboard.copy(url) }
            }
            Button("Stop Quick Tunnel") { tunnels.stopQuickTunnel(tunnel) }
        } else if tunnels.isInstalled {
            Button("Share with Quick Tunnel", systemImage: "cloud") { tunnels.startQuickTunnel(port: port.port) }
        } else {
            Button("Copy “brew install cloudflared”") { Pasteboard.copy(CommandLineTool.cloudflared.installCommand) }
        }
        ForEach(tunnels.exposuresByPort[port.port] ?? [], id: \.publicURL) { exposure in
            Button("Open \(exposure.hostname)") {
                if let url = URL(string: exposure.publicURL) { NSWorkspace.shared.open(url) }
            }
        }
    }
}
