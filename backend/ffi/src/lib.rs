//! UniFFI bindings for portkiller-core library.
//!
//! This crate provides FFI bindings that can be used from Swift via XCFramework.
//! The main entry point is `RustEngine` which wraps all PortKiller functionality.

use portkiller_core::{
    kubernetes::{
        KubernetesNamespace, KubernetesService, PortForwardConnectionConfig,
        PortForwardConnectionState, PortForwardNotification, ServicePort,
    },
    Notification as CoreNotification, PortInfo as CorePortInfo, PortKillerEngine,
    ProcessType as CoreProcessType, WatchedPort as CoreWatchedPort,
};
use uuid::Uuid;

uniffi::include_scaffolding!("lib");

/// Error type exposed via FFI.
#[derive(Debug, thiserror::Error)]
pub enum RustEngineError {
    #[error("Scan failed: {msg}")]
    ScanFailed { msg: String },

    #[error("Kill failed: {msg}")]
    KillFailed { msg: String },

    #[error("Permission denied: {msg}")]
    PermissionDenied { msg: String },

    #[error("Config error: {msg}")]
    ConfigError { msg: String },
}

impl From<portkiller_core::Error> for RustEngineError {
    fn from(e: portkiller_core::Error) -> Self {
        use portkiller_core::Error;
        match e {
            Error::PermissionDenied(msg) => RustEngineError::PermissionDenied { msg },
            Error::KillFailed { pid, reason } => RustEngineError::KillFailed {
                msg: format!("Failed to kill process {}: {}", pid, reason),
            },
            Error::Config(msg) => RustEngineError::ConfigError { msg },
            Error::Kubernetes(ke) => RustEngineError::ConfigError {
                msg: ke.to_string(),
            },
            Error::CommandFailed(msg) => RustEngineError::ScanFailed { msg },
            Error::ParseError(msg) => RustEngineError::ScanFailed { msg },
            Error::Io(e) => RustEngineError::ScanFailed { msg: e.to_string() },
            Error::Json(e) => RustEngineError::ConfigError { msg: e.to_string() },
            Error::UnsupportedPlatform(msg) => RustEngineError::ScanFailed { msg },
        }
    }
}

/// Port information exposed to Swift.
#[derive(Debug, Clone)]
pub struct RustPortInfo {
    pub id: String,
    pub port: u16,
    pub pid: u32,
    pub process_name: String,
    pub address: String,
    pub user: String,
    pub command: String,
    pub fd: String,
    pub is_active: bool,
    pub process_type: String,
}

impl From<CorePortInfo> for RustPortInfo {
    fn from(p: CorePortInfo) -> Self {
        Self {
            id: p.id.to_string(),
            port: p.port,
            pid: p.pid,
            process_name: p.process_name.clone(),
            address: p.address.clone(),
            user: p.user.clone(),
            command: p.command.clone(),
            fd: p.fd.clone(),
            is_active: p.is_active,
            process_type: process_type_to_string(CoreProcessType::detect(&p.process_name)),
        }
    }
}

fn process_type_to_string(pt: CoreProcessType) -> String {
    match pt {
        CoreProcessType::WebServer => "webServer".to_string(),
        CoreProcessType::Database => "database".to_string(),
        CoreProcessType::Development => "development".to_string(),
        CoreProcessType::System => "system".to_string(),
        CoreProcessType::Other => "other".to_string(),
    }
}

/// Watched port information exposed to Swift.
#[derive(Debug, Clone)]
pub struct RustWatchedPort {
    pub id: String,
    pub port: u16,
    pub notify_on_start: bool,
    pub notify_on_stop: bool,
}

impl From<CoreWatchedPort> for RustWatchedPort {
    fn from(wp: CoreWatchedPort) -> Self {
        Self {
            id: wp.id.to_string(),
            port: wp.port,
            notify_on_start: wp.notify_on_start,
            notify_on_stop: wp.notify_on_stop,
        }
    }
}

/// Notification exposed to Swift.
#[derive(Debug, Clone)]
pub struct RustNotification {
    pub notification_type: String,
    pub port: u16,
    pub process_name: Option<String>,
}

impl From<CoreNotification> for RustNotification {
    fn from(n: CoreNotification) -> Self {
        match n {
            CoreNotification::PortStarted { port, process_name } => Self {
                notification_type: "started".to_string(),
                port,
                process_name: Some(process_name),
            },
            CoreNotification::PortStopped { port } => Self {
                notification_type: "stopped".to_string(),
                port,
                process_name: None,
            },
        }
    }
}

// ============================================================================
// Kubernetes FFI Types
// ============================================================================

/// Kubernetes namespace exposed to Swift.
#[derive(Debug, Clone)]
pub struct RustKubernetesNamespace {
    pub name: String,
}

impl From<KubernetesNamespace> for RustKubernetesNamespace {
    fn from(ns: KubernetesNamespace) -> Self {
        Self { name: ns.name }
    }
}

/// Kubernetes service port exposed to Swift.
#[derive(Debug, Clone)]
pub struct RustServicePort {
    pub name: Option<String>,
    pub port: u16,
    pub target_port: u16,
    pub protocol: Option<String>,
}

impl From<ServicePort> for RustServicePort {
    fn from(p: ServicePort) -> Self {
        Self {
            name: p.name,
            port: p.port,
            target_port: p.target_port,
            protocol: p.protocol,
        }
    }
}

/// Kubernetes service exposed to Swift.
#[derive(Debug, Clone)]
pub struct RustKubernetesService {
    pub name: String,
    pub namespace: String,
    pub service_type: String,
    pub cluster_ip: Option<String>,
    pub ports: Vec<RustServicePort>,
}

impl From<KubernetesService> for RustKubernetesService {
    fn from(s: KubernetesService) -> Self {
        Self {
            name: s.name,
            namespace: s.namespace,
            service_type: s.service_type,
            cluster_ip: s.cluster_ip,
            ports: s.ports.into_iter().map(Into::into).collect(),
        }
    }
}

/// Port forward connection config exposed to Swift.
#[derive(Debug, Clone)]
pub struct RustPortForwardConfig {
    pub id: String,
    pub name: String,
    pub namespace: String,
    pub service: String,
    pub local_port: u16,
    pub remote_port: u16,
    pub proxy_port: Option<u16>,
    pub is_enabled: bool,
    pub auto_reconnect: bool,
    pub use_direct_exec: bool,
    pub notify_on_connect: bool,
    pub notify_on_disconnect: bool,
}

impl From<PortForwardConnectionConfig> for RustPortForwardConfig {
    fn from(c: PortForwardConnectionConfig) -> Self {
        Self {
            id: c.id.to_string(),
            name: c.name,
            namespace: c.namespace,
            service: c.service,
            local_port: c.local_port,
            remote_port: c.remote_port,
            proxy_port: c.proxy_port,
            is_enabled: c.is_enabled,
            auto_reconnect: c.auto_reconnect,
            use_direct_exec: c.use_direct_exec,
            notify_on_connect: c.notify_on_connect,
            notify_on_disconnect: c.notify_on_disconnect,
        }
    }
}

impl RustPortForwardConfig {
    fn to_core(&self) -> Result<PortForwardConnectionConfig, RustEngineError> {
        let id = Uuid::parse_str(&self.id).map_err(|e| RustEngineError::ConfigError {
            msg: format!("Invalid UUID: {}", e),
        })?;
        Ok(PortForwardConnectionConfig {
            id,
            name: self.name.clone(),
            namespace: self.namespace.clone(),
            service: self.service.clone(),
            local_port: self.local_port,
            remote_port: self.remote_port,
            proxy_port: self.proxy_port,
            is_enabled: self.is_enabled,
            auto_reconnect: self.auto_reconnect,
            use_direct_exec: self.use_direct_exec,
            notify_on_connect: self.notify_on_connect,
            notify_on_disconnect: self.notify_on_disconnect,
        })
    }
}

/// Port forward connection state exposed to Swift.
#[derive(Debug, Clone)]
pub struct RustPortForwardState {
    pub id: String,
    pub port_forward_status: String,
    pub proxy_status: String,
    pub last_error: Option<String>,
    pub is_intentionally_stopped: bool,
}

impl From<PortForwardConnectionState> for RustPortForwardState {
    fn from(s: PortForwardConnectionState) -> Self {
        Self {
            id: s.id.to_string(),
            port_forward_status: s.port_forward_status.as_str().to_string(),
            proxy_status: s.proxy_status.as_str().to_string(),
            last_error: s.last_error,
            is_intentionally_stopped: s.is_intentionally_stopped,
        }
    }
}

/// Port forward notification exposed to Swift.
#[derive(Debug, Clone)]
pub struct RustPortForwardNotification {
    pub notification_type: String,
    pub connection_id: String,
    pub connection_name: String,
}

impl From<PortForwardNotification> for RustPortForwardNotification {
    fn from(n: PortForwardNotification) -> Self {
        Self {
            notification_type: n.notification_type().to_string(),
            connection_id: n.connection_id().to_string(),
            connection_name: n.connection_name().to_string(),
        }
    }
}

// ============================================================================
// Main Engine
// ============================================================================

/// Main engine interface exposed via FFI.
///
/// This wraps `PortKillerEngine` and provides all functionality
/// needed by the Swift UI layer.
pub struct RustEngine {
    engine: PortKillerEngine,
}

impl RustEngine {
    /// Create a new engine instance.
    pub fn new() -> Result<Self, RustEngineError> {
        let engine = PortKillerEngine::new()?;
        Ok(Self { engine })
    }

    // MARK: - Refresh

    /// Perform a single refresh cycle.
    /// Call this every 5 seconds from Swift.
    pub fn refresh(&self) -> Result<(), RustEngineError> {
        self.engine.refresh()?;
        Ok(())
    }

    // MARK: - State Access

    /// Get all cached ports.
    pub fn get_ports(&self) -> Vec<RustPortInfo> {
        self.engine
            .get_ports()
            .into_iter()
            .map(Into::into)
            .collect()
    }

    /// Check if a specific port is active.
    pub fn is_port_active(&self, port: u16) -> bool {
        self.engine.is_port_active(port)
    }

    // MARK: - Notifications

    /// Get and clear pending notifications.
    pub fn get_pending_notifications(&self) -> Vec<RustNotification> {
        self.engine
            .get_pending_notifications()
            .into_iter()
            .map(Into::into)
            .collect()
    }

    /// Check if there are pending notifications.
    pub fn has_pending_notifications(&self) -> bool {
        self.engine.has_pending_notifications()
    }

    // MARK: - Process Management

    /// Kill a process by port number.
    pub fn kill_port(&self, port: u16) -> Result<bool, RustEngineError> {
        self.engine.kill_port(port).map_err(Into::into)
    }

    /// Kill a process by PID.
    pub fn kill_process(&self, pid: u32, force: bool) -> Result<bool, RustEngineError> {
        self.engine.kill_process(pid, force).map_err(Into::into)
    }

    /// Check if a process is running.
    pub fn is_process_running(&self, pid: u32) -> bool {
        self.engine.is_process_running(pid)
    }

    // MARK: - Favorites

    /// Get all favorite ports.
    pub fn get_favorites(&self) -> Vec<u16> {
        self.engine.get_favorites().into_iter().collect()
    }

    /// Add a port to favorites.
    pub fn add_favorite(&self, port: u16) -> Result<(), RustEngineError> {
        self.engine.add_favorite(port).map_err(Into::into)
    }

    /// Remove a port from favorites.
    pub fn remove_favorite(&self, port: u16) -> Result<(), RustEngineError> {
        self.engine.remove_favorite(port).map_err(Into::into)
    }

    /// Toggle favorite status for a port.
    pub fn toggle_favorite(&self, port: u16) -> Result<bool, RustEngineError> {
        self.engine.toggle_favorite(port).map_err(Into::into)
    }

    /// Check if a port is a favorite.
    pub fn is_favorite(&self, port: u16) -> bool {
        self.engine.is_favorite(port)
    }

    // MARK: - Watched Ports

    /// Get all watched ports.
    pub fn get_watched_ports(&self) -> Vec<RustWatchedPort> {
        self.engine
            .get_watched_ports()
            .into_iter()
            .map(Into::into)
            .collect()
    }

    /// Add a watched port.
    pub fn add_watched_port(
        &self,
        port: u16,
        notify_on_start: bool,
        notify_on_stop: bool,
    ) -> Result<RustWatchedPort, RustEngineError> {
        self.engine
            .add_watched_port(port, notify_on_start, notify_on_stop)
            .map(Into::into)
            .map_err(Into::into)
    }

    /// Remove a watched port.
    pub fn remove_watched_port(&self, port: u16) -> Result<(), RustEngineError> {
        self.engine.remove_watched_port(port).map_err(Into::into)
    }

    /// Update watched port notification settings.
    pub fn update_watched_port(
        &self,
        port: u16,
        notify_on_start: bool,
        notify_on_stop: bool,
    ) -> Result<(), RustEngineError> {
        self.engine
            .update_watched_port(port, notify_on_start, notify_on_stop)
            .map_err(Into::into)
    }

    /// Toggle watch status for a port.
    pub fn toggle_watch(&self, port: u16) -> Result<bool, RustEngineError> {
        self.engine.toggle_watch(port).map_err(Into::into)
    }

    /// Check if a port is being watched.
    pub fn is_watched(&self, port: u16) -> bool {
        self.engine.is_watched(port)
    }

    // MARK: - Config

    /// Reload configuration from disk.
    pub fn reload_config(&self) -> Result<(), RustEngineError> {
        self.engine.reload_config().map_err(Into::into)
    }

    // =========================================================================
    // MARK: - Settings
    // =========================================================================

    /// Get the refresh interval in seconds.
    pub fn get_settings_refresh_interval(&self) -> Result<u64, RustEngineError> {
        self.engine
            .get_settings_refresh_interval()
            .map_err(Into::into)
    }

    /// Set the refresh interval in seconds.
    pub fn set_settings_refresh_interval(&self, interval: u64) -> Result<(), RustEngineError> {
        self.engine
            .set_settings_refresh_interval(interval)
            .map_err(Into::into)
    }

    /// Get port forward auto-start setting.
    pub fn get_settings_port_forward_auto_start(&self) -> Result<bool, RustEngineError> {
        self.engine
            .get_settings_port_forward_auto_start()
            .map_err(Into::into)
    }

    /// Set port forward auto-start setting.
    pub fn set_settings_port_forward_auto_start(
        &self,
        enabled: bool,
    ) -> Result<(), RustEngineError> {
        self.engine
            .set_settings_port_forward_auto_start(enabled)
            .map_err(Into::into)
    }

    /// Get port forward show notifications setting.
    pub fn get_settings_port_forward_show_notifications(&self) -> Result<bool, RustEngineError> {
        self.engine
            .get_settings_port_forward_show_notifications()
            .map_err(Into::into)
    }

    /// Set port forward show notifications setting.
    pub fn set_settings_port_forward_show_notifications(
        &self,
        enabled: bool,
    ) -> Result<(), RustEngineError> {
        self.engine
            .set_settings_port_forward_show_notifications(enabled)
            .map_err(Into::into)
    }

    // =========================================================================
    // MARK: - Kubernetes Discovery
    // =========================================================================

    /// Fetch all Kubernetes namespaces.
    pub fn fetch_namespaces(&self) -> Result<Vec<RustKubernetesNamespace>, RustEngineError> {
        self.engine
            .fetch_namespaces()
            .map(|ns| ns.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }

    /// Fetch services in a specific namespace.
    pub fn fetch_services(
        &self,
        namespace: String,
    ) -> Result<Vec<RustKubernetesService>, RustEngineError> {
        self.engine
            .fetch_services(&namespace)
            .map(|s| s.into_iter().map(Into::into).collect())
            .map_err(Into::into)
    }

    /// Check if kubectl is available.
    pub fn is_kubectl_available(&self) -> bool {
        self.engine.is_kubectl_available()
    }

    /// Check if socat is available.
    pub fn is_socat_available(&self) -> bool {
        self.engine.is_socat_available()
    }

    // =========================================================================
    // MARK: - Kubernetes Port Forward Connections
    // =========================================================================

    /// Get all port forward connections.
    pub fn get_port_forward_connections(&self) -> Vec<RustPortForwardConfig> {
        self.engine
            .get_port_forward_connections()
            .into_iter()
            .map(Into::into)
            .collect()
    }

    /// Add a new port forward connection.
    pub fn add_port_forward_connection(
        &self,
        config: RustPortForwardConfig,
    ) -> Result<(), RustEngineError> {
        let core_config = config.to_core()?;
        self.engine
            .add_port_forward_connection(core_config)
            .map_err(Into::into)
    }

    /// Remove a port forward connection.
    pub fn remove_port_forward_connection(&self, id: String) -> Result<(), RustEngineError> {
        self.engine
            .remove_port_forward_connection(&id)
            .map_err(Into::into)
    }

    /// Update a port forward connection.
    pub fn update_port_forward_connection(
        &self,
        config: RustPortForwardConfig,
    ) -> Result<(), RustEngineError> {
        let core_config = config.to_core()?;
        self.engine
            .update_port_forward_connection(core_config)
            .map_err(Into::into)
    }

    // =========================================================================
    // MARK: - Kubernetes Port Forward Control
    // =========================================================================

    /// Start a port forward connection.
    pub fn start_port_forward(&self, id: String) -> Result<(), RustEngineError> {
        self.engine.start_port_forward(&id).map_err(Into::into)
    }

    /// Stop a port forward connection.
    pub fn stop_port_forward(&self, id: String) -> Result<(), RustEngineError> {
        self.engine.stop_port_forward(&id).map_err(Into::into)
    }

    /// Restart a port forward connection.
    pub fn restart_port_forward(&self, id: String) -> Result<(), RustEngineError> {
        self.engine.restart_port_forward(&id).map_err(Into::into)
    }

    /// Stop all port forward connections.
    pub fn stop_all_port_forwards(&self) -> Result<(), RustEngineError> {
        self.engine.stop_all_port_forwards().map_err(Into::into)
    }

    // =========================================================================
    // MARK: - Kubernetes Port Forward State & Monitoring
    // =========================================================================

    /// Get all port forward connection states.
    pub fn get_port_forward_states(&self) -> Vec<RustPortForwardState> {
        self.engine
            .get_port_forward_states()
            .into_iter()
            .map(Into::into)
            .collect()
    }

    /// Get and clear pending port forward notifications.
    pub fn get_port_forward_notifications(&self) -> Vec<RustPortForwardNotification> {
        self.engine
            .get_port_forward_notifications()
            .into_iter()
            .map(Into::into)
            .collect()
    }

    /// Check if there are pending port forward notifications.
    pub fn has_port_forward_notifications(&self) -> bool {
        self.engine.has_port_forward_notifications()
    }

    /// Monitor port forward connections (call every 1 second).
    pub fn monitor_port_forwards(&self) {
        self.engine.monitor_port_forwards();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_engine_creation() {
        let engine = RustEngine::new();
        assert!(engine.is_ok());
    }

    #[test]
    fn test_get_ports() {
        let engine = RustEngine::new().unwrap();
        let ports = engine.get_ports();
        // Initially empty (no refresh called)
        assert!(ports.is_empty());
    }
}
