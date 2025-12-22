/**
 * RustPortScanner.swift
 * PortKiller
 *
 * Swift wrapper around the Rust PortKillerEngine.
 * All business logic lives in Rust - Swift only renders UI.
 */

import Foundation

/// Wrapper around Rust PortKillerEngine.
///
/// This is NOT an actor - the underlying Rust engine handles thread safety.
/// All methods are synchronous and return cached state from Rust.
final class RustPortScanner: @unchecked Sendable {

    /// The underlying Rust engine instance
    private let engine: RustEngine

    /// Initialize the Rust engine
    init() throws {
        self.engine = try RustEngine()
    }

    // MARK: - Refresh

    /// Perform a single refresh cycle.
    /// Call this every 5 seconds. This scans ports and updates cached state.
    func refresh() throws {
        try engine.refresh()
    }

    // MARK: - Port State (Cached, Fast)

    /// Get all currently cached ports.
    func getPorts() -> [PortInfo] {
        engine.getPorts().map { PortInfo.fromRust($0) }
    }

    /// Check if a specific port is active.
    func isPortActive(port: Int) -> Bool {
        engine.isPortActive(port: UInt16(port))
    }

    // MARK: - Notifications

    /// Get and clear pending notifications.
    /// Returns notifications for watched port state changes.
    func getPendingNotifications() -> [(type: String, port: Int, processName: String?)] {
        engine.getPendingNotifications().map {
            (type: $0.notificationType, port: Int($0.port), processName: $0.processName)
        }
    }

    /// Check if there are pending notifications.
    func hasPendingNotifications() -> Bool {
        engine.hasPendingNotifications()
    }

    // MARK: - Process Management

    /// Kill a process by port number.
    func killPort(_ port: Int) throws -> Bool {
        try engine.killPort(port: UInt16(port))
    }

    /// Kill a process by PID.
    func killProcess(pid: Int, force: Bool = false) throws -> Bool {
        try engine.killProcess(pid: UInt32(pid), force: force)
    }

    /// Check if a process is running.
    func isProcessRunning(pid: Int) -> Bool {
        engine.isProcessRunning(pid: UInt32(pid))
    }

    // MARK: - Favorites

    /// Get all favorite ports.
    func getFavorites() -> Set<Int> {
        Set(engine.getFavorites().map { Int($0) })
    }

    /// Add a port to favorites.
    func addFavorite(port: Int) throws {
        try engine.addFavorite(port: UInt16(port))
    }

    /// Remove a port from favorites.
    func removeFavorite(port: Int) throws {
        try engine.removeFavorite(port: UInt16(port))
    }

    /// Toggle favorite status for a port.
    /// Returns true if now a favorite, false if removed.
    func toggleFavorite(port: Int) throws -> Bool {
        try engine.toggleFavorite(port: UInt16(port))
    }

    /// Check if a port is a favorite.
    func isFavorite(port: Int) -> Bool {
        engine.isFavorite(port: UInt16(port))
    }

    // MARK: - Watched Ports

    /// Get all watched ports.
    func getWatchedPorts() -> [WatchedPort] {
        engine.getWatchedPorts().compactMap { WatchedPort.fromRust($0) }
    }

    /// Add a watched port.
    func addWatchedPort(port: Int, notifyOnStart: Bool = true, notifyOnStop: Bool = true) throws -> WatchedPort? {
        let rustPort = try engine.addWatchedPort(
            port: UInt16(port),
            notifyOnStart: notifyOnStart,
            notifyOnStop: notifyOnStop
        )
        return WatchedPort.fromRust(rustPort)
    }

    /// Remove a watched port.
    func removeWatchedPort(port: Int) throws {
        try engine.removeWatchedPort(port: UInt16(port))
    }

    /// Update watched port notification settings.
    func updateWatchedPort(port: Int, notifyOnStart: Bool, notifyOnStop: Bool) throws {
        try engine.updateWatchedPort(
            port: UInt16(port),
            notifyOnStart: notifyOnStart,
            notifyOnStop: notifyOnStop
        )
    }

    /// Toggle watch status for a port.
    /// Returns true if now watched, false if removed.
    func toggleWatch(port: Int) throws -> Bool {
        try engine.toggleWatch(port: UInt16(port))
    }

    /// Check if a port is being watched.
    func isWatched(port: Int) -> Bool {
        engine.isWatched(port: UInt16(port))
    }

    // MARK: - Config

    /// Reload configuration from disk.
    func reloadConfig() throws {
        try engine.reloadConfig()
    }

    // =========================================================================
    // MARK: - Kubernetes Discovery
    // =========================================================================

    /// Fetch all Kubernetes namespaces.
    func fetchNamespaces() throws -> [KubernetesNamespace] {
        try engine.fetchNamespaces().map { KubernetesNamespace(name: $0.name) }
    }

    /// Fetch services in a specific namespace.
    func fetchServices(namespace: String) throws -> [KubernetesService] {
        try engine.fetchServices(namespace: namespace).map { KubernetesService.fromRust($0) }
    }

    /// Check if kubectl is available.
    func isKubectlAvailable() -> Bool {
        engine.isKubectlAvailable()
    }

    /// Check if socat is available.
    func isSocatAvailable() -> Bool {
        engine.isSocatAvailable()
    }

    // =========================================================================
    // MARK: - Kubernetes Port Forward Connections
    // =========================================================================

    /// Get all port forward connections.
    func getPortForwardConnections() -> [PortForwardConnectionConfig] {
        engine.getPortForwardConnections().map { PortForwardConnectionConfig.fromRust($0) }
    }

    /// Add a new port forward connection.
    func addPortForwardConnection(_ config: PortForwardConnectionConfig) throws {
        try engine.addPortForwardConnection(config: config.toRust())
    }

    /// Remove a port forward connection.
    func removePortForwardConnection(id: UUID) throws {
        try engine.removePortForwardConnection(id: id.uuidString)
    }

    /// Update a port forward connection.
    func updatePortForwardConnection(_ config: PortForwardConnectionConfig) throws {
        try engine.updatePortForwardConnection(config: config.toRust())
    }

    // =========================================================================
    // MARK: - Kubernetes Port Forward Control
    // =========================================================================

    /// Start a port forward connection.
    func startPortForward(id: UUID) throws {
        try engine.startPortForward(id: id.uuidString)
    }

    /// Stop a port forward connection.
    func stopPortForward(id: UUID) throws {
        try engine.stopPortForward(id: id.uuidString)
    }

    /// Restart a port forward connection.
    func restartPortForward(id: UUID) throws {
        try engine.restartPortForward(id: id.uuidString)
    }

    /// Stop all port forward connections.
    func stopAllPortForwards() throws {
        try engine.stopAllPortForwards()
    }

    // =========================================================================
    // MARK: - Kubernetes Port Forward State & Monitoring
    // =========================================================================

    /// Get all port forward connection states.
    func getPortForwardStates() -> [RustPortForwardState] {
        engine.getPortForwardStates()
    }

    /// Get and clear pending port forward notifications.
    func getPortForwardNotifications() -> [RustPortForwardNotification] {
        engine.getPortForwardNotifications()
    }

    /// Check if there are pending port forward notifications.
    func hasPortForwardNotifications() -> Bool {
        engine.hasPortForwardNotifications()
    }

    /// Monitor port forward connections (call every 1 second).
    func monitorPortForwards() {
        engine.monitorPortForwards()
    }

    // =========================================================================
    // MARK: - Settings
    // =========================================================================

    /// Get the refresh interval in seconds.
    func getSettingsRefreshInterval() -> Int {
        (try? Int(engine.getSettingsRefreshInterval())) ?? 5
    }

    /// Set the refresh interval in seconds.
    func setSettingsRefreshInterval(_ interval: Int) {
        try? engine.setSettingsRefreshInterval(interval: UInt64(interval))
    }

    /// Get port forward auto-start setting.
    func getSettingsPortForwardAutoStart() -> Bool {
        (try? engine.getSettingsPortForwardAutoStart()) ?? true
    }

    /// Set port forward auto-start setting.
    func setSettingsPortForwardAutoStart(_ enabled: Bool) {
        try? engine.setSettingsPortForwardAutoStart(enabled: enabled)
    }

    /// Get port forward show notifications setting.
    func getSettingsPortForwardShowNotifications() -> Bool {
        (try? engine.getSettingsPortForwardShowNotifications()) ?? true
    }

    /// Set port forward show notifications setting.
    func setSettingsPortForwardShowNotifications(_ enabled: Bool) {
        try? engine.setSettingsPortForwardShowNotifications(enabled: enabled)
    }
}

// MARK: - PortInfo Extension for Rust Conversion

extension PortInfo {
    /// Create a PortInfo from Rust FFI RustPortInfo
    static func fromRust(_ rustPort: RustPortInfo) -> PortInfo {
        PortInfo.active(
            port: Int(rustPort.port),
            pid: Int(rustPort.pid),
            processName: rustPort.processName,
            address: rustPort.address,
            user: rustPort.user,
            command: rustPort.command,
            fd: rustPort.fd,
            processType: ProcessType.fromRustString(rustPort.processType)
        )
    }
}
