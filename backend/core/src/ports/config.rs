//! Configuration repository port (interface).

use std::collections::HashSet;

use crate::domain::WatchedPort;
use crate::error::Result;

/// Port for configuration persistence.
///
/// This trait defines the interface for storing and retrieving
/// user configuration (favorites, watched ports, settings).
pub trait ConfigRepository: Send + Sync {
    // =========================================================================
    // Favorites
    // =========================================================================

    /// Get all favorite port numbers.
    fn get_favorites(&self) -> impl std::future::Future<Output = Result<HashSet<u16>>> + Send;

    /// Add a port to favorites.
    fn add_favorite(&self, port: u16) -> impl std::future::Future<Output = Result<()>> + Send;

    /// Remove a port from favorites.
    fn remove_favorite(&self, port: u16) -> impl std::future::Future<Output = Result<()>> + Send;

    // =========================================================================
    // Watched Ports
    // =========================================================================

    /// Get all watched ports.
    fn get_watched_ports(
        &self,
    ) -> impl std::future::Future<Output = Result<Vec<WatchedPort>>> + Send;

    /// Add a watched port.
    fn add_watched_port(
        &self,
        port: u16,
    ) -> impl std::future::Future<Output = Result<WatchedPort>> + Send;

    /// Remove a watched port.
    fn remove_watched_port(&self, port: u16)
        -> impl std::future::Future<Output = Result<()>> + Send;

    /// Update watched port notification settings.
    fn update_watched_port(
        &self,
        port: u16,
        notify_on_start: bool,
        notify_on_stop: bool,
    ) -> impl std::future::Future<Output = Result<()>> + Send;

    // =========================================================================
    // Settings
    // =========================================================================

    /// Get the refresh interval in seconds.
    fn get_refresh_interval(&self) -> impl std::future::Future<Output = Result<u64>> + Send;

    /// Set the refresh interval in seconds.
    fn set_refresh_interval(
        &self,
        interval: u64,
    ) -> impl std::future::Future<Output = Result<()>> + Send;

    /// Get port forward auto-start setting.
    fn get_port_forward_auto_start(&self)
        -> impl std::future::Future<Output = Result<bool>> + Send;

    /// Set port forward auto-start setting.
    fn set_port_forward_auto_start(
        &self,
        enabled: bool,
    ) -> impl std::future::Future<Output = Result<()>> + Send;

    /// Get port forward show notifications setting.
    fn get_port_forward_show_notifications(
        &self,
    ) -> impl std::future::Future<Output = Result<bool>> + Send;

    /// Set port forward show notifications setting.
    fn set_port_forward_show_notifications(
        &self,
        enabled: bool,
    ) -> impl std::future::Future<Output = Result<()>> + Send;
}
