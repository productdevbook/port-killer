//! UniFFI bindings for portkiller-core library.
//!
//! This crate provides FFI bindings that can be used from Swift via XCFramework.
//! The main entry point is `RustEngine` which wraps all PortKiller functionality.

use portkiller_core::{
    Notification as CoreNotification, PortInfo as CorePortInfo, PortKillerEngine,
    ProcessType as CoreProcessType, WatchedPort as CoreWatchedPort,
};

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
        let msg = e.to_string();
        if msg.contains("Permission denied") {
            RustEngineError::PermissionDenied { msg }
        } else if msg.contains("kill") || msg.contains("Kill") {
            RustEngineError::KillFailed { msg }
        } else if msg.contains("config") || msg.contains("Config") {
            RustEngineError::ConfigError { msg }
        } else {
            RustEngineError::ScanFailed { msg }
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
        self.engine.get_ports().into_iter().map(Into::into).collect()
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
