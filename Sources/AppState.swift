import Foundation
import SwiftUI
import Defaults
import KeyboardShortcuts
import Sparkle

// MARK: - Defaults Keys

extension Defaults.Keys {
    static let favorites = Key<Set<Int>>("favorites", default: [])
    static let watchedPorts = Key<[WatchedPort]>("watchedPorts", default: [])
    static let useTreeView = Key<Bool>("useTreeView", default: false)
    static let refreshInterval = Key<Int>("refreshInterval", default: 5)

    // Sponsor-related keys
    static let sponsorCache = Key<SponsorCache?>("sponsorCache", default: nil)
    static let lastSponsorWindowShown = Key<Date?>("lastSponsorWindowShown", default: nil)
    static let sponsorDisplayInterval = Key<SponsorDisplayInterval>("sponsorDisplayInterval", default: .bimonthly)
}

// MARK: - Keyboard Shortcuts

extension KeyboardShortcuts.Name {
    static let toggleMainWindow = Self("toggleMainWindow", default: .init(.p, modifiers: [.command, .shift]))
}

// MARK: - App State

/**
 * AppState manages the core application state including:
 * - Port scanning and management
 * - Favorites and watched ports
 * - Filter state for the main window
 * - Keyboard shortcuts
 * - Auto-refresh functionality
 *
 * This class is marked with @Observable for SwiftUI reactivity and
 * @MainActor to ensure all UI updates happen on the main thread.
 */
@Observable
@MainActor
final class AppState {
    // MARK: - Port State

    /// All currently scanned ports
    var ports: [PortInfo] = []

    /// Whether a port scan is currently in progress
    var isScanning = false

    // MARK: - Filter State (for main window)

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

    /**
     * Returns filtered ports based on sidebar selection and active filters.
     * This includes inactive placeholder entries for favorited/watched ports that aren't running.
     */
    var filteredPorts: [PortInfo] {
        // Early return for settings (no ports shown)
        if case .settings = selectedSidebarItem { return [] }

        var result: [PortInfo]

        // Apply sidebar selection
        switch selectedSidebarItem {
        case .allPorts, .settings, .sponsors:
            result = ports
        case .favorites:
            // Single pass: collect active favorites and track which ports are active
            var activePorts = Set<Int>()
            result = ports.compactMap { port -> PortInfo? in
                guard favorites.contains(port.port) else { return nil }
                activePorts.insert(port.port)
                return port
            }
            // Add inactive favorites
            for favPort in favorites where !activePorts.contains(favPort) {
                result.append(PortInfo.inactive(port: favPort))
            }
        case .watched:
            let watchedPortNumbers = Set(watchedPorts.map { $0.port })
            // Single pass: collect active watched and track which ports are active
            var activePorts = Set<Int>()
            result = ports.compactMap { port -> PortInfo? in
                guard watchedPortNumbers.contains(port.port) else { return nil }
                activePorts.insert(port.port)
                return port
            }
            // Add inactive watched
            for watchedPort in watchedPortNumbers where !activePorts.contains(watchedPort) {
                result.append(PortInfo.inactive(port: watchedPort))
            }
        case .processType(let type):
            result = ports.filter { $0.processType == type }
        }

        // Apply additional filters only if needed
        if filter.isActive {
            result = result.filter { filter.matches($0, favorites: favorites, watched: watchedPorts) }
        }

        return result
    }

    // MARK: - Favorites

    /// Cached favorites set, synced with UserDefaults
    private var _favorites: Set<Int> = Defaults[.favorites] {
        didSet { Defaults[.favorites] = _favorites }
    }

    /// Port numbers marked as favorites by the user
    var favorites: Set<Int> {
        get { _favorites }
        set { _favorites = newValue }
    }

    // MARK: - Watched Ports

    /// Cached watched ports array, synced with UserDefaults
    private var _watchedPorts: [WatchedPort] = Defaults[.watchedPorts] {
        didSet { Defaults[.watchedPorts] = _watchedPorts }
    }

    /// Ports being watched for state changes (will trigger notifications)
    var watchedPorts: [WatchedPort] {
        get { _watchedPorts }
        set { _watchedPorts = newValue }
    }

    // MARK: - Update Manager

    /// Manages Sparkle auto-update functionality
    let updateManager = UpdateManager()

    // MARK: - Private Properties

    /// Port scanning actor
    private let scanner = PortScanner()

    /// Background task for auto-refresh
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// Tracks previous port states for watch notifications
    private var previousPortStates: [Int: Bool] = [:]

    // MARK: - Initialization

    init() {
        setupKeyboardShortcuts()
        startAutoRefresh()
    }

    /// Stops the auto-refresh task
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Port Operations

    /**
     * Refreshes the port list by scanning for active ports.
     * Prevents concurrent scans and updates watched port states.
     */
    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let scanned = await scanner.scanPorts()
        updatePorts(scanned)
        checkWatchedPorts()
    }

    /**
     * Updates the internal port list only if there are changes.
     * Sorts ports with favorites first, then by port number.
     */
    private func updatePorts(_ newPorts: [PortInfo]) {
        let newSet = Set(newPorts.map { "\($0.port)-\($0.pid)" })
        let oldSet = Set(ports.map { "\($0.port)-\($0.pid)" })
        guard newSet != oldSet else { return }

        ports = newPorts.sorted { a, b in
            let aFav = favorites.contains(a.port)
            let bFav = favorites.contains(b.port)
            if aFav != bFav { return aFav }
            return a.port < b.port
        }
    }

    /**
     * Kills the process using the specified port.
     * Refreshes the port list after successful termination.
     */
    func killPort(_ port: PortInfo) async {
        if await scanner.killProcessGracefully(pid: port.pid) {
            ports.removeAll { $0.id == port.id }
            await refresh()
        }
    }

    /**
     * Kills all processes currently using ports.
     * This is a destructive operation that terminates all listed processes.
     */
    func killAll() async {
        for port in ports {
            _ = await scanner.killProcessGracefully(pid: port.pid)
        }
        ports.removeAll()
        await refresh()
    }

    // MARK: - Auto Refresh

    /**
     * Starts a background task that periodically refreshes the port list.
     * The refresh interval is configured in user defaults.
     */
    private func startAutoRefresh() {
        refreshTask = Task { @MainActor in
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Defaults[.refreshInterval]))
                if !Task.isCancelled { await self.refresh() }
            }
        }
    }

    // MARK: - Favorites

    /**
     * Toggles favorite status for a port.
     * @param port - The port number to toggle
     */
    func toggleFavorite(_ port: Int) {
        if favorites.contains(port) { favorites.remove(port) }
        else { favorites.insert(port) }
    }

    /**
     * Checks if a port is marked as favorite.
     * @param port - The port number to check
     * @returns True if the port is favorited
     */
    func isFavorite(_ port: Int) -> Bool { favorites.contains(port) }

    // MARK: - Watch

    /**
     * Toggles watch status for a port.
     * When a port is watched, notifications will be sent when it starts/stops.
     * @param port - The port number to toggle
     */
    func toggleWatch(_ port: Int) {
        if let idx = watchedPorts.firstIndex(where: { $0.port == port }) {
            previousPortStates.removeValue(forKey: port)
            watchedPorts.remove(at: idx)
        } else {
            watchedPorts.append(WatchedPort(port: port))
        }
    }

    /**
     * Checks if a port is being watched.
     * @param port - The port number to check
     * @returns True if the port is being watched
     */
    func isWatching(_ port: Int) -> Bool { watchedPorts.contains { $0.port == port } }

    /**
     * Updates notification preferences for a watched port.
     * @param port - The port number to update
     * @param onStart - Whether to notify when port becomes active
     * @param onStop - Whether to notify when port becomes inactive
     */
    func updateWatch(_ port: Int, onStart: Bool, onStop: Bool) {
        if let idx = watchedPorts.firstIndex(where: { $0.port == port }) {
            watchedPorts[idx].notifyOnStart = onStart
            watchedPorts[idx].notifyOnStop = onStop
        }
    }

    /**
     * Removes a watched port by its ID.
     * @param id - The UUID of the watched port to remove
     */
    func removeWatch(_ id: UUID) {
        if let w = watchedPorts.first(where: { $0.id == id }) {
            previousPortStates.removeValue(forKey: w.port)
        }
        watchedPorts.removeAll { $0.id == id }
    }

    /**
     * Checks watched ports for state changes and triggers notifications.
     * This is called after each port scan to detect when watched ports start or stop.
     */
    private func checkWatchedPorts() {
        let activePorts = Set(ports.map { $0.port })
        for w in watchedPorts {
            let isActive = activePorts.contains(w.port)
            if let wasActive = previousPortStates[w.port] {
                if wasActive && !isActive && w.notifyOnStop {
                    NotificationService.shared.notify(
                        title: "Port \(w.port) Available",
                        body: "Port is now free."
                    )
                } else if !wasActive && isActive && w.notifyOnStart {
                    let name = ports.first { $0.port == w.port }?.processName ?? "Unknown"
                    NotificationService.shared.notify(
                        title: "Port \(w.port) In Use",
                        body: "Used by \(name)."
                    )
                }
            }
            previousPortStates[w.port] = isActive
        }
    }

    // MARK: - Keyboard Shortcuts

    /**
     * Sets up global keyboard shortcuts.
     * Currently handles: Cmd+Shift+P to toggle main window
     */
    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleMainWindow) { [weak self] in
            Task { @MainActor in
                self?.toggleMainWindow()
            }
        }
    }

    /**
     * Toggles the main window visibility.
     * - If window is visible: hides it
     * - If window is hidden: shows it and brings app to front
     * - If window doesn't exist: activates app (creates new window)
     */
    private func toggleMainWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "PortKiller" || $0.identifier?.rawValue == "main" }) {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
