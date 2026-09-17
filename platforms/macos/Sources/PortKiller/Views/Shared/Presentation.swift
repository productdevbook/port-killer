import PortKillerKit
import SwiftUI

extension PortScope {
    var title: String {
        switch self {
        case .all: "All Ports"
        case .favorites: "Favorites"
        case .watched: "Watched"
        }
    }

    var sectionTitle: String {
        switch self {
        case .all: "Ports"
        case .favorites: "Favorites"
        case .watched: "Watched"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: "No Listening Ports"
        case .favorites: "No Favorites"
        case .watched: "No Watched Ports"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "Processes that listen on TCP ports appear here."
        case .favorites: "Mark a port as a favorite to keep it here, even when nothing listens on it."
        case .watched: "Watch a port to get notified when it starts or stops being used."
        }
    }
}

extension Optional where Wrapped == PluginItemStatus {
    var title: String {
        switch self {
        case .running: "Running"
        case .stopped: "Stopped"
        case .warning: "Warning"
        case .error: "Error"
        case nil: "—"
        }
    }

    var tint: Color {
        switch self {
        case .running: .green
        case .stopped, nil: .secondary
        case .warning: .orange
        case .error: .red
        }
    }

    var iconTint: Color {
        switch self {
        case .running: .accentColor
        case .stopped, nil: .secondary
        case .warning: .orange
        case .error: .red
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
