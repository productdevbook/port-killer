import Foundation
import SwiftUI
import Defaults
import KeyboardShortcuts
import Sparkle

// MARK: - Defaults Keys

extension Defaults.Keys {
    // Note: favorites and watchedPorts are now stored in Rust config (~/.portkiller/config.json)
    // This enables sharing between the macOS app and CLI
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

/// AppState manages the core application state.
///
/// All business logic (scanning, notifications, state tracking) is in Rust.
/// Swift only handles UI state and rendering.
@Observable
@MainActor
final class AppState {
    // MARK: - Port State (from Rust)

    /// All currently cached ports (from Rust engine)
    private(set) var ports: [PortInfo] = []

    /// Whether a port scan is currently in progress
    private(set) var isScanning = false

    // MARK: - UI State

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

    // MARK: - Filtered Ports (Computed)

    /// Returns filtered ports based on sidebar selection and active filters.
    var filteredPorts: [PortInfo] {
        if case .settings = selectedSidebarItem { return [] }

        var result: [PortInfo]
        let favs = favorites
        let watched = watchedPorts

        switch selectedSidebarItem {
        case .allPorts, .settings, .sponsors, .kubernetesPortForward, .cloudflareTunnels:
            result = ports
        case .favorites:
            var activePorts = Set<Int>()
            result = ports.compactMap { port -> PortInfo? in
                guard favs.contains(port.port) else { return nil }
                activePorts.insert(port.port)
                return port
            }
            for favPort in favs where !activePorts.contains(favPort) {
                result.append(PortInfo.inactive(port: favPort))
            }
        case .watched:
            let watchedPortNumbers = Set(watched.map { $0.port })
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
            result = result.filter { filter.matches($0, favorites: favs, watched: watched) }
        }

        return result
    }

    // MARK: - Favorites (from Rust)

    /// Port numbers marked as favorites (read from Rust)
    var favorites: Set<Int> {
        scanner.getFavorites()
    }

    // MARK: - Watched Ports (from Rust)

    /// Ports being watched for state changes (read from Rust)
    var watchedPorts: [WatchedPort] {
        scanner.getWatchedPorts()
    }

    // MARK: - Managers

    /// Manages Sparkle auto-update functionality
    let updateManager = UpdateManager()

    /// Manages Kubernetes port-forward connections
    let portForwardManager = PortForwardManager()

    /// Manages Cloudflare tunnel connections
    let tunnelManager = TunnelManager()

    // MARK: - Internal Properties

    /// Rust engine wrapper - all business logic lives here
    let scanner: RustPortScanner

    /// Timer for periodic UI refresh
    @ObservationIgnored private var refreshTimer: Timer?

    // MARK: - Initialization

    init() {
        // Initialize Rust engine
        do {
            scanner = try RustPortScanner()
        } catch {
            fatalError("Failed to initialize Rust engine: \(error)")
        }

        setupKeyboardShortcuts()
        startAutoRefresh()
    }

    // MARK: - Auto Refresh

    /// Start the auto-refresh timer.
    func startAutoRefresh() {
        stopAutoRefresh()

        // Initial refresh
        refresh()

        // Schedule periodic refresh
        let interval = TimeInterval(Defaults[.refreshInterval])
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// Stop the auto-refresh timer.
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Perform a single refresh cycle.
    /// Runs the heavy Rust scanning on a background thread to avoid blocking the main thread.
    func refresh() {
        guard !isScanning else { return }
        isScanning = true

        // Run Rust scanning on background thread to avoid blocking main thread
        Task.detached(priority: .userInitiated) { [scanner] in
            do {
                // Tell Rust to scan ports (this blocks but on background thread)
                try scanner.refresh()
            } catch {
                #if DEBUG
                print("Refresh error: \(error)")
                #endif
            }

            // Update UI on main thread
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.ports = scanner.getPorts()
                self.processNotifications()
                self.isScanning = false
            }
        }
    }

    /// Process pending notifications from Rust engine.
    private func processNotifications() {
        let notifications = scanner.getPendingNotifications()

        for notification in notifications {
            switch notification.type {
            case "started":
                NotificationService.shared.notify(
                    title: "Port \(notification.port) In Use",
                    body: "Used by \(notification.processName ?? "Unknown")."
                )
            case "stopped":
                NotificationService.shared.notify(
                    title: "Port \(notification.port) Available",
                    body: "Port is now free."
                )
            default:
                break
            }
        }
    }

    // MARK: - Port Operations

    /// Kill a process on a specific port.
    func killPort(_ port: PortInfo) {
        do {
            _ = try scanner.killPort(port.port)
            // Refresh to update UI
            refresh()
        } catch {
            #if DEBUG
            print("Kill port error: \(error)")
            #endif
        }
    }

    /// Kill all ports in the current filtered list.
    func killAll() {
        for port in filteredPorts where port.isActive {
            do {
                _ = try scanner.killPort(port.port)
            } catch {
                #if DEBUG
                print("Kill port \(port.port) error: \(error)")
                #endif
            }
        }
        refresh()
    }

    // MARK: - Favorites Operations

    /// Toggle favorite status for a port.
    func toggleFavorite(_ port: Int) {
        do {
            _ = try scanner.toggleFavorite(port: port)
        } catch {
            #if DEBUG
            print("Toggle favorite error: \(error)")
            #endif
        }
    }

    /// Check if a port is a favorite.
    func isFavorite(_ port: Int) -> Bool {
        scanner.isFavorite(port: port)
    }

    // MARK: - Watch Operations

    /// Toggle watch status for a port.
    func toggleWatch(_ port: Int) {
        do {
            _ = try scanner.toggleWatch(port: port)
        } catch {
            #if DEBUG
            print("Toggle watch error: \(error)")
            #endif
        }
    }

    /// Check if a port is being watched.
    func isWatching(_ port: Int) -> Bool {
        scanner.isWatched(port: port)
    }

    /// Update watch notification settings.
    func updateWatch(_ port: Int, onStart: Bool, onStop: Bool) {
        do {
            try scanner.updateWatchedPort(port: port, notifyOnStart: onStart, notifyOnStop: onStop)
        } catch {
            #if DEBUG
            print("Update watch error: \(error)")
            #endif
        }
    }

    /// Remove a watched port by ID.
    func removeWatch(_ id: UUID) {
        if let wp = watchedPorts.first(where: { $0.id == id }) {
            do {
                try scanner.removeWatchedPort(port: wp.port)
            } catch {
                #if DEBUG
                print("Remove watch error: \(error)")
                #endif
            }
        }
    }

    /// Add a watched port.
    func addWatchedPort(port: Int, notifyOnStart: Bool = true, notifyOnStop: Bool = true) {
        do {
            _ = try scanner.addWatchedPort(port: port, notifyOnStart: notifyOnStart, notifyOnStop: notifyOnStop)
        } catch {
            #if DEBUG
            print("Add watched port error: \(error)")
            #endif
        }
    }
}
