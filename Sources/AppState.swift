import Foundation
import SwiftUI
import Defaults
import KeyboardShortcuts
import Sparkle

// MARK: - Defaults Keys (app-specific, not shared with CLI)

extension Defaults.Keys {
    static let useTreeView = Key<Bool>("useTreeView", default: false)
    static let refreshInterval = Key<Int>("refreshInterval", default: 5)

    // Sponsor-related keys
    static let sponsorCache = Key<SponsorCache?>("sponsorCache", default: nil)
    static let lastSponsorWindowShown = Key<Date?>("lastSponsorWindowShown", default: nil)
    static let sponsorDisplayInterval = Key<SponsorDisplayInterval>("sponsorDisplayInterval", default: .bimonthly)
}

// MARK: - Keyboard Shortcuts

extension KeyboardShortcuts.Name {
    static let toggleMainWindow = Self("toggleMainWindow")
}

// MARK: - App State

/// AppState manages the core application state including ports, favorites,
/// watched ports, filters, keyboard shortcuts, and auto-refresh functionality.
@Observable
@MainActor
final class AppState {
    // MARK: - Port State

    /// All currently scanned ports
    var ports: [PortInfo] = []

    /// Whether a port scan is currently in progress
    var isScanning = false

    // MARK: - Filter State

    /// Current filter settings for the port list
    var filter = PortFilter()

    /// Currently selected sidebar item (affects which ports are shown)
    var selectedSidebarItem: SidebarItem = .allPorts

    /// ID of the currently selected port in the detail view
    var selectedPortID: UUID? = nil

    /// The currently selected port, if any
    var selectedPort: PortInfo? {
        guard let id = selectedPortID else { return nil }
        return ports.first { $0.id == id }
    }

    /// ID of the currently selected port-forward connection
    var selectedPortForwardConnectionId: UUID? = nil

    /// The currently selected port-forward connection, if any
    var selectedPortForwardConnection: PortForwardConnectionState? {
        guard let id = selectedPortForwardConnectionId else { return nil }
        return portForwardManager.connections.first { $0.id == id }
    }

    /// Returns filtered ports based on sidebar selection and active filters.
    var filteredPorts: [PortInfo] {
        if case .settings = selectedSidebarItem { return [] }

        var result: [PortInfo]

        switch selectedSidebarItem {
        case .allPorts, .settings, .sponsors, .kubernetesPortForward, .cloudflareTunnels:
            result = ports
        case .favorites:
            var activePorts = Set<Int>()
            result = ports.compactMap { port -> PortInfo? in
                guard favorites.contains(port.port) else { return nil }
                activePorts.insert(port.port)
                return port
            }
            for favPort in favorites where !activePorts.contains(favPort) {
                result.append(PortInfo.inactive(port: favPort))
            }
        case .watched:
            let watchedPortNumbers = Set(watchedPorts.map { $0.port })
            var activePorts = Set<Int>()
            result = ports.compactMap { port -> PortInfo? in
                guard watchedPortNumbers.contains(port.port) else { return nil }
                activePorts.insert(port.port)
                return port
            }
            for watchedPort in watchedPortNumbers where !activePorts.contains(watchedPort) {
                result.append(PortInfo.inactive(port: watchedPort))
            }
        case .processType(let type):
            result = ports.filter { $0.processType == type }
        }

        if filter.isActive {
            result = result.filter { filter.matches($0, favorites: favorites, watched: watchedPorts) }
        }

        return result
    }

    // MARK: - Favorites (synced with CLI via ~/.portkiller/config.json)

    /// Cached favorites set
    private var _favorites: Set<Int> = SharedConfigStore.shared.favorites {
        didSet { SharedConfigStore.shared.favorites = _favorites }
    }

    /// Port numbers marked as favorites by the user
    var favorites: Set<Int> {
        get { _favorites }
        set { _favorites = newValue }
    }

    // MARK: - Watched Ports (synced with CLI via ~/.portkiller/config.json)

    /// Cached watched ports array
    private var _watchedPorts: [WatchedPort] = SharedConfigStore.shared.watchedPorts {
        didSet { SharedConfigStore.shared.watchedPorts = _watchedPorts }
    }

    /// Ports being watched for state changes
    var watchedPorts: [WatchedPort] {
        get { _watchedPorts }
        set { _watchedPorts = newValue }
    }

    // MARK: - Managers

    /// Manages Sparkle auto-update functionality
    let updateManager = UpdateManager()

    /// Manages Kubernetes port-forward connections
    let portForwardManager = PortForwardManager()

    /// Manages Cloudflare tunnel connections
    let tunnelManager = TunnelManager()

    // MARK: - Internal Properties (for extensions)

    /// Port scanning actor
    let scanner = PortScanner()

    /// Background task for auto-refresh
    @ObservationIgnored var refreshTask: Task<Void, Never>?

    /// Tracks previous port states for watch notifications
    var previousPortStates: [Int: Bool] = [:]

    // MARK: - Initialization

    init() {
        setupKeyboardShortcuts()
        startAutoRefresh()
        setupConfigSync()
    }

    // MARK: - Config Sync with CLI

    /// Set up file watching for shared config
    private func setupConfigSync() {
        SharedConfigStore.shared.onConfigChanged = { [weak self] in
            self?.reloadFromSharedConfig()
        }
    }

    /// Reload config from shared JSON file
    func reloadFromSharedConfig() {
        let diskFavorites = SharedConfigStore.shared.favorites
        if _favorites != diskFavorites {
            _favorites = diskFavorites
        }

        let diskWatchedPorts = SharedConfigStore.shared.watchedPorts
        if _watchedPorts != diskWatchedPorts {
            _watchedPorts = diskWatchedPorts
        }
    }
}
