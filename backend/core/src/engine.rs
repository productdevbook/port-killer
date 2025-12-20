//! PortKiller Engine - Central state management and auto-refresh.
//!
//! This module provides the main engine that manages port scanning,
//! state caching, notifications, and auto-refresh functionality.
//! All business logic lives here, making Swift UI a thin layer.

use parking_lot::RwLock;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use tokio::runtime::{Builder, Runtime};

use crate::config::ConfigStore;
use crate::error::Result;
use crate::killer::ProcessKiller;
use crate::kubernetes::{
    KubernetesConnectionManager, KubernetesNamespace, KubernetesService,
    PortForwardConnectionConfig, PortForwardConnectionState, PortForwardNotification,
};
use crate::models::{filter_ports, PortFilter, PortInfo, WatchedPort};
use crate::scanner::PortScanner;

/// Notification types for port state changes.
#[derive(Debug, Clone)]
pub enum Notification {
    /// Port became active (process started listening)
    PortStarted { port: u16, process_name: String },
    /// Port became inactive (process stopped listening)
    PortStopped { port: u16 },
}

/// The main PortKiller engine.
///
/// Manages all port scanning, state tracking, and business logic.
/// Swift UI should only poll this engine for state updates.
///
/// # Usage Pattern
/// Swift calls `refresh()` periodically (e.g., every 5 seconds).
/// Between refreshes, Swift reads cached state via `get_ports()`, etc.
pub struct PortKillerEngine {
    // Components
    scanner: PortScanner,
    killer: ProcessKiller,
    config: ConfigStore,
    runtime: Runtime,

    // Kubernetes
    kubernetes: KubernetesConnectionManager,

    // State (protected by RwLock for thread safety)
    ports: RwLock<Vec<PortInfo>>,
    previous_states: RwLock<HashMap<u16, bool>>,
    pending_notifications: RwLock<Vec<Notification>>,

    // Refresh tracking
    refresh_running: AtomicBool,
    refresh_interval_secs: AtomicU64,

    // Cached config (avoid repeated disk reads)
    favorites_cache: RwLock<HashSet<u16>>,
    watched_cache: RwLock<Vec<WatchedPort>>,
}

impl PortKillerEngine {
    /// Ensure the config directory exists.
    fn ensure_config_dir() -> Result<()> {
        let config_dir = dirs::home_dir()
            .ok_or_else(|| {
                crate::error::Error::Config("Could not find home directory".to_string())
            })?
            .join(".portkiller");

        std::fs::create_dir_all(&config_dir).map_err(|e| {
            crate::error::Error::Config(format!("Failed to create config directory: {}", e))
        })?;

        Ok(())
    }

    /// Create a new engine instance.
    pub fn new() -> Result<Self> {
        // Ensure config directory exists before anything else
        Self::ensure_config_dir()?;

        // Use single-threaded runtime - lighter on resources for GUI app
        let runtime = Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| crate::error::Error::Config(format!("Failed to create runtime: {}", e)))?;
        let config = ConfigStore::new()?;

        // Load initial config
        let favorites = runtime.block_on(config.get_favorites())?;
        let watched = runtime.block_on(config.get_watched_ports())?;

        // Create Kubernetes connection manager
        let kubernetes = KubernetesConnectionManager::new().map_err(|e| {
            crate::error::Error::Config(format!("Failed to create Kubernetes manager: {}", e))
        })?;

        // Load Kubernetes connections
        runtime
            .block_on(kubernetes.reload_connections())
            .map_err(|e| {
                crate::error::Error::Config(format!("Failed to load Kubernetes connections: {}", e))
            })?;

        Ok(Self {
            scanner: PortScanner::new(),
            killer: ProcessKiller::new(),
            config,
            runtime,
            kubernetes,
            ports: RwLock::new(Vec::new()),
            previous_states: RwLock::new(HashMap::new()),
            pending_notifications: RwLock::new(Vec::new()),
            refresh_running: AtomicBool::new(false),
            refresh_interval_secs: AtomicU64::new(5),
            favorites_cache: RwLock::new(favorites),
            watched_cache: RwLock::new(watched),
        })
    }

    /// Set the refresh interval (in seconds).
    ///
    /// Note: The actual refresh is triggered by Swift calling `refresh()`.
    /// This just stores the preferred interval for reference.
    pub fn set_refresh_interval(&self, interval_secs: u64) {
        self.refresh_interval_secs
            .store(interval_secs, Ordering::SeqCst);
    }

    /// Get the current refresh interval (in seconds).
    pub fn get_refresh_interval(&self) -> u64 {
        self.refresh_interval_secs.load(Ordering::SeqCst)
    }

    /// Mark refresh as started (for UI state).
    pub fn set_refreshing(&self, is_refreshing: bool) {
        self.refresh_running.store(is_refreshing, Ordering::SeqCst);
    }

    /// Check if auto-refresh is running.
    pub fn is_auto_refresh_running(&self) -> bool {
        self.refresh_running.load(Ordering::SeqCst)
    }

    /// Perform a single refresh cycle.
    ///
    /// This should be called periodically (e.g., every 5 seconds).
    /// It scans ports, updates state, and generates notifications.
    pub fn refresh(&self) -> Result<()> {
        // Scan ports
        let new_ports = self.runtime.block_on(self.scanner.scan())?;

        // Get watched ports for notifications
        let watched = self.watched_cache.read().clone();

        // Check for state changes and generate notifications
        self.check_watched_ports(&new_ports, &watched);

        // Update cached ports
        *self.ports.write() = new_ports;

        Ok(())
    }

    /// Check watched ports for state changes and generate notifications.
    fn check_watched_ports(&self, new_ports: &[PortInfo], watched: &[WatchedPort]) {
        let active_ports: HashSet<u16> = new_ports.iter().map(|p| p.port).collect();
        let mut prev_states = self.previous_states.write();
        let mut notifications = self.pending_notifications.write();

        for w in watched {
            let is_active = active_ports.contains(&w.port);

            if let Some(&was_active) = prev_states.get(&w.port) {
                // State changed
                if was_active && !is_active && w.notify_on_stop {
                    notifications.push(Notification::PortStopped { port: w.port });
                } else if !was_active && is_active && w.notify_on_start {
                    let process_name = new_ports
                        .iter()
                        .find(|p| p.port == w.port)
                        .map(|p| p.process_name.clone())
                        .unwrap_or_else(|| "Unknown".to_string());
                    notifications.push(Notification::PortStarted {
                        port: w.port,
                        process_name,
                    });
                }
            }

            prev_states.insert(w.port, is_active);
        }

        // Clean up: remove states for ports that are no longer watched
        let watched_ports: HashSet<u16> = watched.iter().map(|w| w.port).collect();
        prev_states.retain(|port, _| watched_ports.contains(port));
    }

    // MARK: - Port State Access

    /// Get all currently cached ports.
    pub fn get_ports(&self) -> Vec<PortInfo> {
        self.ports.read().clone()
    }

    /// Get filtered ports based on the provided filter.
    pub fn get_filtered_ports(&self, filter: &PortFilter) -> Vec<PortInfo> {
        let ports = self.ports.read();
        let favorites = self.favorites_cache.read();
        let watched = self.watched_cache.read();

        filter_ports(&ports, filter, &favorites, &watched)
    }

    /// Check if a specific port is currently active.
    pub fn is_port_active(&self, port: u16) -> bool {
        self.ports.read().iter().any(|p| p.port == port)
    }

    // MARK: - Notifications

    /// Get and clear pending notifications.
    pub fn get_pending_notifications(&self) -> Vec<Notification> {
        std::mem::take(&mut *self.pending_notifications.write())
    }

    /// Check if there are pending notifications.
    pub fn has_pending_notifications(&self) -> bool {
        !self.pending_notifications.read().is_empty()
    }

    // MARK: - Process Management

    /// Kill a process by port number.
    pub fn kill_port(&self, port: u16) -> Result<bool> {
        let ports = self.ports.read();
        if let Some(port_info) = ports.iter().find(|p| p.port == port) {
            self.runtime
                .block_on(self.killer.kill_gracefully(port_info.pid))
        } else {
            Ok(false)
        }
    }

    /// Kill a process by PID.
    pub fn kill_process(&self, pid: u32, force: bool) -> Result<bool> {
        if force {
            self.runtime.block_on(self.killer.kill(pid, true))
        } else {
            self.runtime.block_on(self.killer.kill_gracefully(pid))
        }
    }

    /// Check if a process is running.
    pub fn is_process_running(&self, pid: u32) -> bool {
        self.killer.is_running(pid)
    }

    // MARK: - Favorites

    /// Get all favorite ports.
    pub fn get_favorites(&self) -> HashSet<u16> {
        self.favorites_cache.read().clone()
    }

    /// Add a port to favorites.
    pub fn add_favorite(&self, port: u16) -> Result<()> {
        self.runtime.block_on(self.config.add_favorite(port))?;
        self.favorites_cache.write().insert(port);
        Ok(())
    }

    /// Remove a port from favorites.
    pub fn remove_favorite(&self, port: u16) -> Result<()> {
        self.runtime.block_on(self.config.remove_favorite(port))?;
        self.favorites_cache.write().remove(&port);
        Ok(())
    }

    /// Toggle favorite status for a port.
    pub fn toggle_favorite(&self, port: u16) -> Result<bool> {
        let is_favorite = self.favorites_cache.read().contains(&port);
        if is_favorite {
            self.remove_favorite(port)?;
            Ok(false)
        } else {
            self.add_favorite(port)?;
            Ok(true)
        }
    }

    /// Check if a port is a favorite.
    pub fn is_favorite(&self, port: u16) -> bool {
        self.favorites_cache.read().contains(&port)
    }

    // MARK: - Watched Ports

    /// Get all watched ports.
    pub fn get_watched_ports(&self) -> Vec<WatchedPort> {
        self.watched_cache.read().clone()
    }

    /// Add a watched port.
    pub fn add_watched_port(
        &self,
        port: u16,
        notify_on_start: bool,
        notify_on_stop: bool,
    ) -> Result<WatchedPort> {
        let wp = self.runtime.block_on(self.config.add_watched_port(port))?;

        // Update notification settings if different from defaults
        if !notify_on_start || !notify_on_stop {
            self.runtime.block_on(self.config.update_watched_port(
                port,
                notify_on_start,
                notify_on_stop,
            ))?;
        }

        let mut wp_updated = wp.clone();
        wp_updated.notify_on_start = notify_on_start;
        wp_updated.notify_on_stop = notify_on_stop;

        self.watched_cache.write().push(wp_updated.clone());
        Ok(wp_updated)
    }

    /// Remove a watched port.
    pub fn remove_watched_port(&self, port: u16) -> Result<()> {
        self.runtime
            .block_on(self.config.remove_watched_port(port))?;
        self.watched_cache.write().retain(|w| w.port != port);

        // Clean up previous state
        self.previous_states.write().remove(&port);

        Ok(())
    }

    /// Update watched port notification settings.
    pub fn update_watched_port(
        &self,
        port: u16,
        notify_on_start: bool,
        notify_on_stop: bool,
    ) -> Result<()> {
        self.runtime.block_on(self.config.update_watched_port(
            port,
            notify_on_start,
            notify_on_stop,
        ))?;

        if let Some(wp) = self
            .watched_cache
            .write()
            .iter_mut()
            .find(|w| w.port == port)
        {
            wp.notify_on_start = notify_on_start;
            wp.notify_on_stop = notify_on_stop;
        }

        Ok(())
    }

    /// Toggle watch status for a port.
    pub fn toggle_watch(&self, port: u16) -> Result<bool> {
        let is_watched = self.watched_cache.read().iter().any(|w| w.port == port);
        if is_watched {
            self.remove_watched_port(port)?;
            Ok(false)
        } else {
            self.add_watched_port(port, true, true)?;
            Ok(true)
        }
    }

    /// Check if a port is being watched.
    pub fn is_watched(&self, port: u16) -> bool {
        self.watched_cache.read().iter().any(|w| w.port == port)
    }

    // MARK: - Configuration

    /// Reload configuration from disk.
    pub fn reload_config(&self) -> Result<()> {
        let favorites = self.runtime.block_on(self.config.get_favorites())?;
        let watched = self.runtime.block_on(self.config.get_watched_ports())?;

        *self.favorites_cache.write() = favorites;
        *self.watched_cache.write() = watched;

        // Reload Kubernetes connections
        self.runtime
            .block_on(self.kubernetes.reload_connections())
            .map_err(|e| {
                crate::error::Error::Config(format!(
                    "Failed to reload Kubernetes connections: {}",
                    e
                ))
            })?;

        Ok(())
    }

    // =========================================================================
    // MARK: - Settings
    // =========================================================================

    /// Get the refresh interval in seconds.
    pub fn get_settings_refresh_interval(&self) -> Result<u64> {
        self.runtime.block_on(self.config.get_refresh_interval())
    }

    /// Set the refresh interval in seconds.
    pub fn set_settings_refresh_interval(&self, interval: u64) -> Result<()> {
        self.runtime
            .block_on(self.config.set_refresh_interval(interval))
    }

    /// Get port forward auto-start setting.
    pub fn get_settings_port_forward_auto_start(&self) -> Result<bool> {
        self.runtime
            .block_on(self.config.get_port_forward_auto_start())
    }

    /// Set port forward auto-start setting.
    pub fn set_settings_port_forward_auto_start(&self, enabled: bool) -> Result<()> {
        self.runtime
            .block_on(self.config.set_port_forward_auto_start(enabled))
    }

    /// Get port forward show notifications setting.
    pub fn get_settings_port_forward_show_notifications(&self) -> Result<bool> {
        self.runtime
            .block_on(self.config.get_port_forward_show_notifications())
    }

    /// Set port forward show notifications setting.
    pub fn set_settings_port_forward_show_notifications(&self, enabled: bool) -> Result<()> {
        self.runtime
            .block_on(self.config.set_port_forward_show_notifications(enabled))
    }

    // =========================================================================
    // MARK: - Kubernetes Discovery
    // =========================================================================

    /// Fetches all Kubernetes namespaces.
    pub fn fetch_namespaces(&self) -> Result<Vec<KubernetesNamespace>> {
        self.runtime
            .block_on(self.kubernetes.fetch_namespaces())
            .map_err(|e| crate::error::Error::CommandFailed(e.to_string()))
    }

    /// Fetches services in a specific namespace.
    pub fn fetch_services(&self, namespace: &str) -> Result<Vec<KubernetesService>> {
        self.runtime
            .block_on(self.kubernetes.fetch_services(namespace))
            .map_err(|e| crate::error::Error::CommandFailed(e.to_string()))
    }

    /// Returns true if kubectl is available.
    pub fn is_kubectl_available(&self) -> bool {
        self.kubernetes.is_kubectl_available()
    }

    /// Returns true if socat is available.
    pub fn is_socat_available(&self) -> bool {
        self.kubernetes.is_socat_available()
    }

    // =========================================================================
    // MARK: - Kubernetes Port Forward Connections
    // =========================================================================

    /// Gets all port forward connections.
    pub fn get_port_forward_connections(&self) -> Vec<PortForwardConnectionConfig> {
        self.kubernetes.get_connections_cached()
    }

    /// Adds a new port forward connection.
    pub fn add_port_forward_connection(&self, config: PortForwardConnectionConfig) -> Result<()> {
        self.runtime
            .block_on(self.kubernetes.add_connection(config))
            .map_err(|e| crate::error::Error::Config(e.to_string()))
    }

    /// Removes a port forward connection.
    pub fn remove_port_forward_connection(&self, id: &str) -> Result<()> {
        let uuid = uuid::Uuid::parse_str(id)
            .map_err(|e| crate::error::Error::Config(format!("Invalid UUID: {}", e)))?;
        self.runtime
            .block_on(self.kubernetes.remove_connection(uuid))
            .map_err(|e| crate::error::Error::Config(e.to_string()))
    }

    /// Updates a port forward connection.
    pub fn update_port_forward_connection(
        &self,
        config: PortForwardConnectionConfig,
    ) -> Result<()> {
        self.runtime
            .block_on(self.kubernetes.update_connection(config))
            .map_err(|e| crate::error::Error::Config(e.to_string()))
    }

    // =========================================================================
    // MARK: - Kubernetes Port Forward Control
    // =========================================================================

    /// Starts a port forward connection.
    pub fn start_port_forward(&self, id: &str) -> Result<()> {
        let uuid = uuid::Uuid::parse_str(id)
            .map_err(|e| crate::error::Error::Config(format!("Invalid UUID: {}", e)))?;
        self.kubernetes
            .start_connection(uuid)
            .map_err(|e| crate::error::Error::CommandFailed(e.to_string()))
    }

    /// Stops a port forward connection.
    pub fn stop_port_forward(&self, id: &str) -> Result<()> {
        let uuid = uuid::Uuid::parse_str(id)
            .map_err(|e| crate::error::Error::Config(format!("Invalid UUID: {}", e)))?;
        self.kubernetes
            .stop_connection(uuid)
            .map_err(|e| crate::error::Error::CommandFailed(e.to_string()))
    }

    /// Restarts a port forward connection.
    pub fn restart_port_forward(&self, id: &str) -> Result<()> {
        let uuid = uuid::Uuid::parse_str(id)
            .map_err(|e| crate::error::Error::Config(format!("Invalid UUID: {}", e)))?;
        self.kubernetes
            .restart_connection(uuid)
            .map_err(|e| crate::error::Error::CommandFailed(e.to_string()))
    }

    /// Stops all port forward connections.
    pub fn stop_all_port_forwards(&self) -> Result<()> {
        self.kubernetes
            .stop_all()
            .map_err(|e| crate::error::Error::CommandFailed(e.to_string()))
    }

    // =========================================================================
    // MARK: - Kubernetes Port Forward State & Monitoring
    // =========================================================================

    /// Gets all port forward connection states.
    pub fn get_port_forward_states(&self) -> Vec<PortForwardConnectionState> {
        self.kubernetes.get_states()
    }

    /// Gets a single port forward connection state.
    pub fn get_port_forward_state(&self, id: &str) -> Option<PortForwardConnectionState> {
        let uuid = uuid::Uuid::parse_str(id).ok()?;
        self.kubernetes.get_state(uuid)
    }

    /// Gets and clears pending port forward notifications.
    pub fn get_port_forward_notifications(&self) -> Vec<PortForwardNotification> {
        self.kubernetes.get_pending_notifications()
    }

    /// Checks if there are pending port forward notifications.
    pub fn has_port_forward_notifications(&self) -> bool {
        self.kubernetes.has_pending_notifications()
    }

    /// Monitors port forward connections and performs auto-reconnect if needed.
    ///
    /// This should be called periodically (e.g., every 1 second).
    pub fn monitor_port_forwards(&self) {
        self.kubernetes.monitor_connections();
    }
}

impl Default for PortKillerEngine {
    fn default() -> Self {
        Self::new().expect("Failed to create PortKillerEngine")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_creation() {
        let engine = PortKillerEngine::new();
        assert!(engine.is_ok());
    }

    #[test]
    fn test_get_ports_initially_empty() {
        let engine = PortKillerEngine::new().unwrap();
        assert!(engine.get_ports().is_empty());
    }

    #[test]
    fn test_refresh_interval() {
        let engine = PortKillerEngine::new().unwrap();
        assert_eq!(engine.get_refresh_interval(), 5);

        engine.set_refresh_interval(10);
        assert_eq!(engine.get_refresh_interval(), 10);
    }

    #[test]
    fn test_refreshing_state() {
        let engine = PortKillerEngine::new().unwrap();
        assert!(!engine.is_auto_refresh_running());

        engine.set_refreshing(true);
        assert!(engine.is_auto_refresh_running());

        engine.set_refreshing(false);
        assert!(!engine.is_auto_refresh_running());
    }
}
