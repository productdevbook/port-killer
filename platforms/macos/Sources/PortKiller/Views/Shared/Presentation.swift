import PortKillerKit
import SwiftUI

extension SidebarItem {
    var title: String {
        switch self {
        case .allPorts: "All Ports"
        case .favorites: "Favorites"
        case .watched: "Watched"
        case .category(let category): category.rawValue
        case .portForwards: "Port Forwards"
        case .tunnels: "Cloudflare Tunnels"
        case .sponsors: "Sponsors"
        }
    }

    var symbolName: String {
        switch self {
        case .allPorts: "network"
        case .favorites: "star"
        case .watched: "eye"
        case .category(let category): category.symbolName
        case .portForwards: "point.3.connected.trianglepath.dotted"
        case .tunnels: "cloud"
        case .sponsors: "heart"
        }
    }
}

extension PortForwardSession.Status {
    var title: String {
        switch self {
        case .stopped: "Stopped"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .waitingToReconnect: "Reconnecting…"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .stopped: .secondary
        case .connecting, .waitingToReconnect, .stopping: .orange
        case .connected: .green
        case .failed: .red
        }
    }
}

extension QuickTunnel.Status {
    var title: String {
        switch self {
        case .starting: "Starting…"
        case .active: "Active"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .starting, .stopping: .orange
        case .active: .green
        case .failed: .red
        }
    }
}

extension NamedTunnel {
    var statusTitle: String {
        switch status {
        case .stopped: runSafety == .managedElsewhere ? "Managed Elsewhere" : "Stopped"
        case .starting: "Starting…"
        case .running: activeConnections == 1 ? "Running · 1 connection" : "Running · \(activeConnections) connections"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch status {
        case .running: .green
        case .starting, .stopping: .orange
        case .failed: .red
        case .stopped: runSafety == .managedElsewhere ? .orange : .secondary
        }
    }
}
