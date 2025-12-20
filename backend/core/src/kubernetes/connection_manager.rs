//! High-level Kubernetes connection management.
//!
//! Provides connection lifecycle management, state tracking, and monitoring.

use parking_lot::RwLock;
use std::collections::HashMap;
use std::time::Duration;

use uuid::Uuid;

use super::config_store::KubernetesConfigStore;
use super::discovery::KubernetesDiscovery;
use super::errors::{KubectlError, Result};
use super::models::{
    KubernetesNamespace, KubernetesService, PortForwardConnectionConfig,
    PortForwardConnectionState, PortForwardNotification, PortForwardProcessType, PortForwardStatus,
};
use super::process_manager::PortForwardProcessManager;

/// Stabilization delay after starting kubectl port-forward.
const PORT_FORWARD_STABILIZATION: Duration = Duration::from_secs(2);

/// Stabilization delay after starting proxy.
const PROXY_STABILIZATION: Duration = Duration::from_secs(1);

/// Manages Kubernetes port forward connections.
pub struct KubernetesConnectionManager {
    discovery: KubernetesDiscovery,
    config_store: KubernetesConfigStore,
    process_manager: PortForwardProcessManager,

    /// Runtime connection states.
    states: RwLock<HashMap<Uuid, PortForwardConnectionState>>,

    /// Pending notifications.
    pending_notifications: RwLock<Vec<PortForwardNotification>>,

    /// Cached connection configs.
    configs_cache: RwLock<Vec<PortForwardConnectionConfig>>,
}

impl KubernetesConnectionManager {
    /// Creates a new connection manager.
    pub fn new() -> Result<Self> {
        // Ensure config directory exists
        let config_dir = dirs::home_dir()
            .ok_or_else(|| KubectlError::ConfigError("Could not find home directory".to_string()))?
            .join(".portkiller");

        std::fs::create_dir_all(&config_dir).map_err(|e| {
            KubectlError::ConfigError(format!("Failed to create config directory: {}", e))
        })?;

        // Clean up any orphan processes from previous runs
        let _ = std::process::Command::new("pkill")
            .args(["-f", "pf-wrapper-"])
            .status();

        Ok(Self {
            discovery: KubernetesDiscovery::new(),
            config_store: KubernetesConfigStore::new()?,
            process_manager: PortForwardProcessManager::new(),
            states: RwLock::new(HashMap::new()),
            pending_notifications: RwLock::new(Vec::new()),
            configs_cache: RwLock::new(Vec::new()),
        })
    }

    // =========================================================================
    // Discovery
    // =========================================================================

    /// Fetches all Kubernetes namespaces.
    pub async fn fetch_namespaces(&self) -> Result<Vec<KubernetesNamespace>> {
        self.discovery.fetch_namespaces().await
    }

    /// Fetches services in a specific namespace.
    pub async fn fetch_services(&self, namespace: &str) -> Result<Vec<KubernetesService>> {
        self.discovery.fetch_services(namespace).await
    }

    /// Returns true if kubectl is available.
    pub fn is_kubectl_available(&self) -> bool {
        self.discovery.is_kubectl_available()
    }

    /// Returns true if socat is available.
    pub fn is_socat_available(&self) -> bool {
        self.discovery.is_socat_available()
    }

    // =========================================================================
    // Connection Configuration
    // =========================================================================

    /// Gets all port forward connections.
    pub async fn get_connections(&self) -> Result<Vec<PortForwardConnectionConfig>> {
        let connections = self.config_store.get_connections().await?;
        *self.configs_cache.write() = connections.clone();
        Ok(connections)
    }

    /// Gets cached connections (fast, no disk I/O).
    pub fn get_connections_cached(&self) -> Vec<PortForwardConnectionConfig> {
        self.configs_cache.read().clone()
    }

    /// Gets a single connection by ID.
    pub async fn get_connection(&self, id: Uuid) -> Result<Option<PortForwardConnectionConfig>> {
        self.config_store.get_connection(id).await
    }

    /// Adds a new port forward connection.
    pub async fn add_connection(&self, config: PortForwardConnectionConfig) -> Result<()> {
        self.config_store.add_connection(config.clone()).await?;

        // Initialize state
        self.states
            .write()
            .insert(config.id, PortForwardConnectionState::new(config.id));

        // Update cache
        self.configs_cache.write().push(config);

        Ok(())
    }

    /// Removes a port forward connection.
    pub async fn remove_connection(&self, id: Uuid) -> Result<()> {
        // Stop if running
        self.stop_connection(id)?;

        // Remove from config
        self.config_store.remove_connection(id).await?;

        // Remove state
        self.states.write().remove(&id);

        // Update cache
        self.configs_cache.write().retain(|c| c.id != id);

        Ok(())
    }

    /// Updates a port forward connection.
    pub async fn update_connection(&self, config: PortForwardConnectionConfig) -> Result<()> {
        self.config_store.update_connection(config.clone()).await?;

        // Update cache
        if let Some(cached) = self
            .configs_cache
            .write()
            .iter_mut()
            .find(|c| c.id == config.id)
        {
            *cached = config;
        }

        Ok(())
    }

    /// Reloads connections from disk.
    pub async fn reload_connections(&self) -> Result<()> {
        let connections = self.config_store.get_connections().await?;
        *self.configs_cache.write() = connections.clone();

        // Initialize states for any new connections
        let mut states = self.states.write();
        for conn in connections {
            states
                .entry(conn.id)
                .or_insert_with(|| PortForwardConnectionState::new(conn.id));
        }

        Ok(())
    }

    // =========================================================================
    // Connection Lifecycle
    // =========================================================================

    /// Starts a port forward connection.
    pub fn start_connection(&self, id: Uuid) -> Result<()> {
        // Check if already connected or connecting - don't restart
        if let Some(state) = self.states.read().get(&id) {
            if state.port_forward_status == PortForwardStatus::Connected
                || state.port_forward_status == PortForwardStatus::Connecting
            {
                return Ok(()); // Already running or starting
            }
        }

        let configs = self.configs_cache.read();
        let config = configs
            .iter()
            .find(|c| c.id == id)
            .ok_or_else(|| KubectlError::ConnectionNotFound(id.to_string()))?
            .clone();
        drop(configs);

        // Update state to connecting
        self.update_state(id, |state| {
            state.port_forward_status = PortForwardStatus::Connecting;
            state.is_intentionally_stopped = false;
            state.last_error = None;
        });

        // Start based on mode
        if config.use_direct_exec {
            // Direct exec mode: single process handles everything
            self.process_manager.start_direct_exec_proxy(id, &config)?;

            // Wait for stabilization
            std::thread::sleep(PROXY_STABILIZATION);

            // Check if port is open
            let effective_port = config.effective_port();
            if self.process_manager.is_port_open(effective_port) {
                self.update_state(id, |state| {
                    state.port_forward_status = PortForwardStatus::Connected;
                    state.proxy_status = PortForwardStatus::Connected;
                });
                self.add_connected_notification(id, &config.name);
            } else {
                self.update_state(id, |state| {
                    state.port_forward_status = PortForwardStatus::Error;
                    state.last_error = Some("Failed to establish connection".to_string());
                });
            }
        } else {
            // Standard mode: kubectl port-forward + optional proxy
            self.process_manager.start_port_forward(id, &config)?;

            // Wait for kubectl to stabilize
            std::thread::sleep(PORT_FORWARD_STABILIZATION);

            // Check if port-forward is working
            if self.process_manager.is_port_open(config.local_port) {
                self.update_state(id, |state| {
                    state.port_forward_status = PortForwardStatus::Connected;
                });

                // Start proxy if configured
                if let Some(proxy_port) = config.proxy_port {
                    self.update_state(id, |state| {
                        state.proxy_status = PortForwardStatus::Connecting;
                    });

                    self.process_manager
                        .start_proxy(id, proxy_port, config.local_port)?;

                    // Wait for proxy to stabilize
                    std::thread::sleep(PROXY_STABILIZATION);

                    if self.process_manager.is_port_open(proxy_port) {
                        self.update_state(id, |state| {
                            state.proxy_status = PortForwardStatus::Connected;
                        });
                    } else {
                        self.update_state(id, |state| {
                            state.proxy_status = PortForwardStatus::Error;
                            state.last_error = Some("Proxy failed to start".to_string());
                        });
                    }
                }

                self.add_connected_notification(id, &config.name);
            } else {
                self.update_state(id, |state| {
                    state.port_forward_status = PortForwardStatus::Error;
                    state.last_error = Some("Port forward failed to establish".to_string());
                });
            }
        }

        Ok(())
    }

    /// Stops a port forward connection.
    pub fn stop_connection(&self, id: Uuid) -> Result<()> {
        let config_name = self
            .configs_cache
            .read()
            .iter()
            .find(|c| c.id == id)
            .map(|c| c.name.clone());

        // Kill processes
        self.process_manager.kill_processes(id)?;

        // Check if was connected before stopping
        let was_connected = self
            .states
            .read()
            .get(&id)
            .map(|s| s.port_forward_status == PortForwardStatus::Connected)
            .unwrap_or(false);

        // Update state
        self.update_state(id, |state| {
            state.port_forward_status = PortForwardStatus::Disconnected;
            state.proxy_status = PortForwardStatus::Disconnected;
            state.is_intentionally_stopped = true;
        });

        // Send disconnect notification if was connected
        if was_connected {
            if let Some(name) = config_name {
                let should_notify = self
                    .configs_cache
                    .read()
                    .iter()
                    .find(|c| c.id == id)
                    .map(|c| c.notify_on_disconnect)
                    .unwrap_or(false);

                if should_notify {
                    self.add_disconnected_notification(id, &name);
                }
            }
        }

        Ok(())
    }

    /// Restarts a port forward connection.
    pub fn restart_connection(&self, id: Uuid) -> Result<()> {
        self.stop_connection(id)?;
        std::thread::sleep(Duration::from_millis(500));
        self.start_connection(id)
    }

    /// Stops all connections.
    pub fn stop_all(&self) -> Result<()> {
        self.process_manager.kill_all()?;

        // Update all states
        let mut states = self.states.write();
        for state in states.values_mut() {
            state.port_forward_status = PortForwardStatus::Disconnected;
            state.proxy_status = PortForwardStatus::Disconnected;
            state.is_intentionally_stopped = true;
        }

        Ok(())
    }

    // =========================================================================
    // State Access
    // =========================================================================

    /// Gets all connection states.
    pub fn get_states(&self) -> Vec<PortForwardConnectionState> {
        self.states.read().values().cloned().collect()
    }

    /// Gets a single connection state.
    pub fn get_state(&self, id: Uuid) -> Option<PortForwardConnectionState> {
        self.states.read().get(&id).cloned()
    }

    // =========================================================================
    // Monitoring
    // =========================================================================

    /// Monitors all connections and performs auto-reconnect if needed.
    ///
    /// This should be called periodically (e.g., every 1 second).
    pub fn monitor_connections(&self) {
        let configs = self.configs_cache.read().clone();

        for config in configs {
            if !config.is_enabled || !config.auto_reconnect {
                continue;
            }

            let state = match self.states.read().get(&config.id).cloned() {
                Some(s) => s,
                None => continue,
            };

            // Skip if intentionally stopped
            if state.is_intentionally_stopped {
                continue;
            }

            // Skip if already connecting - don't double-start
            if state.port_forward_status == PortForwardStatus::Connecting {
                continue;
            }

            // Check if we need to reconnect
            let needs_reconnect = self.check_connection_health(&config, &state);

            if needs_reconnect {
                // Add disconnect notification if was connected
                if state.port_forward_status == PortForwardStatus::Connected
                    && config.notify_on_disconnect
                {
                    self.add_disconnected_notification(config.id, &config.name);
                }

                // Attempt reconnect
                let _ = self.restart_connection(config.id);
            }
        }
    }

    /// Checks if a connection is healthy and returns true if reconnect is needed.
    fn check_connection_health(
        &self,
        config: &PortForwardConnectionConfig,
        _state: &PortForwardConnectionState,
    ) -> bool {
        // Check for recent errors
        if self.process_manager.has_recent_error(config.id) {
            return true;
        }

        // Check process status
        if config.use_direct_exec {
            // Direct exec mode: single proxy process
            if !self
                .process_manager
                .is_process_running(config.id, PortForwardProcessType::Proxy)
            {
                return true;
            }

            // Check port health
            let effective_port = config.effective_port();
            if !self.process_manager.is_port_open(effective_port) {
                return true;
            }
        } else {
            // Standard mode
            if !self
                .process_manager
                .is_process_running(config.id, PortForwardProcessType::PortForward)
            {
                return true;
            }

            // Check port-forward port
            if !self.process_manager.is_port_open(config.local_port) {
                return true;
            }

            // Check proxy if configured
            if let Some(proxy_port) = config.proxy_port {
                if !self
                    .process_manager
                    .is_process_running(config.id, PortForwardProcessType::Proxy)
                {
                    // Just restart proxy, not full connection
                    let _ =
                        self.process_manager
                            .start_proxy(config.id, proxy_port, config.local_port);
                    return false;
                }

                if !self.process_manager.is_port_open(proxy_port) {
                    return true;
                }
            }
        }

        false
    }

    // =========================================================================
    // Notifications
    // =========================================================================

    /// Gets and clears pending notifications.
    pub fn get_pending_notifications(&self) -> Vec<PortForwardNotification> {
        std::mem::take(&mut *self.pending_notifications.write())
    }

    /// Checks if there are pending notifications.
    pub fn has_pending_notifications(&self) -> bool {
        !self.pending_notifications.read().is_empty()
    }

    fn add_connected_notification(&self, id: Uuid, name: &str) {
        let config = self
            .configs_cache
            .read()
            .iter()
            .find(|c| c.id == id)
            .cloned();

        if let Some(config) = config {
            if config.notify_on_connect {
                // Check if we already have a pending connected notification for this id
                let notifications = self.pending_notifications.read();
                let already_pending = notifications.iter().any(|n| {
                    matches!(n, PortForwardNotification::Connected { connection_id, .. } if *connection_id == id)
                });
                drop(notifications);

                if !already_pending {
                    self.pending_notifications
                        .write()
                        .push(PortForwardNotification::Connected {
                            connection_id: id,
                            connection_name: name.to_string(),
                        });
                }
            }
        }
    }

    fn add_disconnected_notification(&self, id: Uuid, name: &str) {
        self.pending_notifications
            .write()
            .push(PortForwardNotification::Disconnected {
                connection_id: id,
                connection_name: name.to_string(),
            });
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    fn update_state<F>(&self, id: Uuid, updater: F)
    where
        F: FnOnce(&mut PortForwardConnectionState),
    {
        let mut states = self.states.write();
        if let Some(state) = states.get_mut(&id) {
            updater(state);
        } else {
            // Create new state if doesn't exist
            let mut new_state = PortForwardConnectionState::new(id);
            updater(&mut new_state);
            states.insert(id, new_state);
        }
    }
}

impl Default for KubernetesConnectionManager {
    fn default() -> Self {
        Self::new().expect("Failed to create KubernetesConnectionManager")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_connection_manager_creation() {
        let manager = KubernetesConnectionManager::new();
        assert!(manager.is_ok());
    }
}
