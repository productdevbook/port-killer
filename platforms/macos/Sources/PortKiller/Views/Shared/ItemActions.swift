import AppKit
import PortKillerKit
import SwiftUI

struct ItemActions: View {
    @Environment(AppModel.self) private var model
    let id: ItemID

    var body: some View {
        switch id {
        case .process(let pid):
            if let item = model.ports.process(pid: pid) {
                ProcessActions(ports: item.ports)
            }
        case .inactivePort(let port):
            Button("Remove Port \(String(port))", systemImage: "minus.circle") { model.ports.removeInactive(port) }
        case .forward(let sessionID):
            if let session = model.forwards.sessions.first(where: { $0.id == sessionID }) {
                ForwardActions(session: session)
            }
        case .quickTunnel(let tunnelID):
            if let tunnel = model.tunnels.quickTunnels.first(where: { $0.id == tunnelID }) {
                if let url = tunnel.url {
                    URLActions(url: url)
                    Divider()
                }
                Button("Stop Sharing", systemImage: "stop", role: .destructive) { model.tunnels.stopQuickTunnel(tunnel) }
            }
        case .namedTunnel(let tunnelID):
            if let tunnel = model.tunnels.namedTunnels.first(where: { $0.id == tunnelID }) {
                if tunnel.isRunningHere {
                    Button("Stop Tunnel", systemImage: "stop", role: .destructive) { model.tunnels.stop(tunnel) }
                } else if tunnel.runSafety == .managedElsewhere {
                    Button("Run Anyway", systemImage: "play") { model.tunnels.run(tunnel, allowManagedElsewhere: true) }
                } else {
                    Button("Run Tunnel", systemImage: "play") { model.tunnels.run(tunnel) }
                }
                Divider()
                Button("Copy Tunnel ID", systemImage: "doc.on.doc") { Pasteboard.copy(tunnel.id) }
            }
        case .pluginItem(let pluginID, let itemID):
            if let plugin = model.plugins.itemPlugins.first(where: { $0.id == pluginID }),
               let item = model.plugins.items[pluginID]?.first(where: { $0.id == itemID }) {
                if let url = item.url {
                    URLActions(url: url)
                    Divider()
                }
                ForEach(item.actions ?? []) { action in
                    Button(action.title, systemImage: action.icon ?? "circle", role: action.destructive == true ? .destructive : nil) {
                        Task { await model.plugins.perform(action, on: item, in: plugin) }
                    }
                }
            }
        }
    }
}

struct ProcessActions: View {
    @Environment(AppModel.self) private var model
    let ports: [ListeningPort]
    var onKill: (() -> Void)?

    var body: some View {
        if let first = ports.first {
            let preferences = model.preferences
            let numbers = ports.map(\.port)
            let isFavorite = numbers.allSatisfy { preferences.favorites.contains($0) }
            let isWatching = numbers.allSatisfy { preferences.isWatching($0) }
            if let url = first.localURL {
                URLActions(url: url)
            }
            Menu("Copy") {
                Button(numbers.count == 1 ? "Port Number" : "Port Numbers") { Pasteboard.copy(numbers.map(String.init).joined(separator: ", ")) }
                Button("Process ID") { Pasteboard.copy(String(first.pid)) }
                Button("Command") { Pasteboard.copy(first.process.command) }
                if let path = first.process.executablePath {
                    Button("Executable Path") { Pasteboard.copy(path) }
                }
            }

            Divider()

            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: "star") {
                for port in numbers where preferences.favorites.contains(port) == isFavorite {
                    preferences.toggleFavorite(port)
                }
            }
            Button(isWatching ? "Stop Watching" : "Watch", systemImage: "eye") {
                for port in numbers where preferences.isWatching(port) == isWatching {
                    preferences.toggleWatch(port)
                }
            }
            Menu("Category") {
                let current = model.ports.category(for: first)
                ForEach(ProcessCategory.allCases) { category in
                    Toggle(category.rawValue, isOn: Binding(
                        get: { current == category },
                        set: { _ in preferences.setCategoryOverride(category, for: first.processName) }
                    ))
                }
                if preferences.categoryOverride(for: first.processName) != nil {
                    Divider()
                    Button("Detect Automatically") { preferences.setCategoryOverride(nil, for: first.processName) }
                }
            }

            Divider()

            let tunnels = model.tunnels
            if let tunnel = tunnels.quickTunnel(for: first.port), tunnel.status != .failed {
                if let url = tunnel.url {
                    Button("Copy Tunnel URL", systemImage: "bolt") { Pasteboard.copy(url.absoluteString) }
                }
                Button("Stop Sharing", systemImage: "bolt.slash") { tunnels.stopQuickTunnel(tunnel) }
            } else if tunnels.isInstalled {
                Button("Share with Quick Tunnel", systemImage: "bolt") { tunnels.startQuickTunnel(port: first.port) }
            }

            let pluginActions = ports.flatMap { port in model.plugins.portActions(for: port).map { (port, $0.plugin, $0.action) } }
            if !pluginActions.isEmpty {
                Divider()
                ForEach(Array(pluginActions.enumerated()), id: \.offset) { _, entry in
                    Button(entry.2.title, systemImage: entry.2.icon ?? entry.1.manifest.icon ?? "puzzlepiece.extension") {
                        Task { await model.plugins.perform(entry.2, on: entry.0, in: entry.1) }
                    }
                }
            }

            Divider()

            if let path = first.process.executablePath {
                Button("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
                }
            }
            Button("Show in PortKiller", systemImage: "macwindow") {
                model.reveal(.process(first.pid))
            }
            Button("Kill \(first.processName)…", systemImage: "xmark.octagon", role: .destructive) {
                if let onKill {
                    onKill()
                } else {
                    model.ports.requestKill(ports)
                }
            }
        }
    }
}

struct ForwardActions: View {
    @Environment(AppModel.self) private var model
    let session: PortForwardSession

    var body: some View {
        if session.isActive {
            Button("Stop", systemImage: "stop") { session.stop() }
            Button("Restart", systemImage: "arrow.clockwise") { session.restart() }
        } else {
            Button("Start", systemImage: "play") { session.start() }
        }
        Divider()
        if let url = session.configuration.localURL {
            URLActions(url: url)
        }
        Divider()
        Button("Start All", systemImage: "play.circle") { model.forwards.startAll() }
        Button("Stop All", systemImage: "stop.circle") { model.forwards.stopAll() }
            .disabled(model.forwards.activeCount == 0)
        Button("Kill Stuck Processes", systemImage: "bandage") {
            Task { await model.forwards.killStuckProcesses() }
        }
        .disabled(model.forwards.isKillingStuckProcesses)
        Divider()
        Button("Duplicate", systemImage: "plus.square.on.square") {
            var copy = session.configuration
            copy.id = UUID()
            copy.name += " Copy"
            model.addForward(copy)
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.forwards.remove(session.id)
        }
    }
}
