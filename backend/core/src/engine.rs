//! PortKiller Engine - Central state management and auto-refresh.
//!
//! This module provides the main engine that manages port scanning,
//! state caching, notifications, and auto-refresh functionality.
//! All business logic lives here, making Swift UI a thin layer.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::RwLock;

use tokio::runtime::Runtime;

use crate::config::ConfigStore;
use crate::error::Result;
use crate::killer::ProcessKiller;
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
    /// Create a new engine instance.
    pub fn new() -> Result<Self> {
        let runtime = Runtime::new()
            .map_err(|e| crate::error::Error::Config(format!("Failed to create runtime: {}", e)))?;
        let config = ConfigStore::new()?;

        // Load initial config
        let favorites = runtime.block_on(config.get_favorites())?;
        let watched = runtime.block_on(config.get_watched_ports())?;

        Ok(Self {
            scanner: PortScanner::new(),
            killer: ProcessKiller::new(),
            config,
            runtime,
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
        self.refresh_interval_secs.store(interval_secs, Ordering::SeqCst);
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
        let watched = self.watched_cache.read().unwrap().clone();

        // Check for state changes and generate notifications
        self.check_watched_ports(&new_ports, &watched);

        // Update cached ports
        *self.ports.write().unwrap() = new_ports;

        Ok(())
    }

    /// Check watched ports for state changes and generate notifications.
    fn check_watched_ports(&self, new_ports: &[PortInfo], watched: &[WatchedPort]) {
        let active_ports: HashSet<u16> = new_ports.iter().map(|p| p.port).collect();
        let mut prev_states = self.previous_states.write().unwrap();
        let mut notifications = self.pending_notifications.write().unwrap();

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
        self.ports.read().unwrap().clone()
    }

    /// Get filtered ports based on the provided filter.
    pub fn get_filtered_ports(&self, filter: &PortFilter) -> Vec<PortInfo> {
        let ports = self.ports.read().unwrap();
        let favorites = self.favorites_cache.read().unwrap();
        let watched = self.watched_cache.read().unwrap();

        filter_ports(&ports, filter, &favorites, &watched)
    }

    /// Check if a specific port is currently active.
    pub fn is_port_active(&self, port: u16) -> bool {
        self.ports.read().unwrap().iter().any(|p| p.port == port)
    }

    // MARK: - Notifications

    /// Get and clear pending notifications.
    pub fn get_pending_notifications(&self) -> Vec<Notification> {
        std::mem::take(&mut *self.pending_notifications.write().unwrap())
    }

    /// Check if there are pending notifications.
    pub fn has_pending_notifications(&self) -> bool {
        !self.pending_notifications.read().unwrap().is_empty()
    }

    // MARK: - Process Management

    /// Kill a process by port number.
    pub fn kill_port(&self, port: u16) -> Result<bool> {
        let ports = self.ports.read().unwrap();
        if let Some(port_info) = ports.iter().find(|p| p.port == port) {
            self.runtime.block_on(self.killer.kill_gracefully(port_info.pid))
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
        self.favorites_cache.read().unwrap().clone()
    }

    /// Add a port to favorites.
    pub fn add_favorite(&self, port: u16) -> Result<()> {
        self.runtime.block_on(self.config.add_favorite(port))?;
        self.favorites_cache.write().unwrap().insert(port);
        Ok(())
    }

    /// Remove a port from favorites.
    pub fn remove_favorite(&self, port: u16) -> Result<()> {
        self.runtime.block_on(self.config.remove_favorite(port))?;
        self.favorites_cache.write().unwrap().remove(&port);
        Ok(())
    }

    /// Toggle favorite status for a port.
    pub fn toggle_favorite(&self, port: u16) -> Result<bool> {
        let is_favorite = self.favorites_cache.read().unwrap().contains(&port);
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
        self.favorites_cache.read().unwrap().contains(&port)
    }

    // MARK: - Watched Ports

    /// Get all watched ports.
    pub fn get_watched_ports(&self) -> Vec<WatchedPort> {
        self.watched_cache.read().unwrap().clone()
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
            self.runtime.block_on(
                self.config.update_watched_port(port, notify_on_start, notify_on_stop)
            )?;
        }

        let mut wp_updated = wp.clone();
        wp_updated.notify_on_start = notify_on_start;
        wp_updated.notify_on_stop = notify_on_stop;

        self.watched_cache.write().unwrap().push(wp_updated.clone());
        Ok(wp_updated)
    }

    /// Remove a watched port.
    pub fn remove_watched_port(&self, port: u16) -> Result<()> {
        self.runtime.block_on(self.config.remove_watched_port(port))?;
        self.watched_cache.write().unwrap().retain(|w| w.port != port);

        // Clean up previous state
        self.previous_states.write().unwrap().remove(&port);

        Ok(())
    }

    /// Update watched port notification settings.
    pub fn update_watched_port(
        &self,
        port: u16,
        notify_on_start: bool,
        notify_on_stop: bool,
    ) -> Result<()> {
        self.runtime.block_on(
            self.config.update_watched_port(port, notify_on_start, notify_on_stop)
        )?;

        if let Some(wp) = self.watched_cache.write().unwrap().iter_mut().find(|w| w.port == port) {
            wp.notify_on_start = notify_on_start;
            wp.notify_on_stop = notify_on_stop;
        }

        Ok(())
    }

    /// Toggle watch status for a port.
    pub fn toggle_watch(&self, port: u16) -> Result<bool> {
        let is_watched = self.watched_cache.read().unwrap().iter().any(|w| w.port == port);
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
        self.watched_cache.read().unwrap().iter().any(|w| w.port == port)
    }

    // MARK: - Configuration

    /// Reload configuration from disk.
    pub fn reload_config(&self) -> Result<()> {
        let favorites = self.runtime.block_on(self.config.get_favorites())?;
        let watched = self.runtime.block_on(self.config.get_watched_ports())?;

        *self.favorites_cache.write().unwrap() = favorites;
        *self.watched_cache.write().unwrap() = watched;

        Ok(())
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
