//! Configuration management for favorites and watched ports.
//!
//! Stores configuration in JSON format at `~/.portkiller/config.json`.
//! This format is compatible with the Swift macOS app for seamless sync.

use std::collections::HashSet;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use tokio::fs;
use tokio::io::AsyncWriteExt;

use crate::error::{Error, Result};
use crate::domain::WatchedPort;

/// Configuration data stored in JSON format.
///
/// This structure matches the Swift app's SharedConfig format for compatibility.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// List of favorite port numbers.
    #[serde(default)]
    pub favorites: Vec<u16>,

    /// List of watched ports with notification settings.
    #[serde(default, rename = "watchedPorts")]
    pub watched_ports: Vec<WatchedPortJson>,

    /// Port scan refresh interval in seconds.
    #[serde(default = "default_refresh_interval", rename = "refreshInterval")]
    pub refresh_interval: u64,

    /// Auto-start port forward connections on app launch.
    #[serde(default = "default_true", rename = "portForwardAutoStart")]
    pub port_forward_auto_start: bool,

    /// Show notifications for port forward status changes.
    #[serde(default = "default_true", rename = "portForwardShowNotifications")]
    pub port_forward_show_notifications: bool,
}

fn default_refresh_interval() -> u64 {
    5
}

impl Default for Config {
    fn default() -> Self {
        Self {
            favorites: Vec::new(),
            watched_ports: Vec::new(),
            refresh_interval: default_refresh_interval(),
            port_forward_auto_start: true,
            port_forward_show_notifications: true,
        }
    }
}

/// JSON representation of a watched port (matches Swift app format).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WatchedPortJson {
    /// UUID as string.
    pub id: String,

    /// Port number.
    pub port: u16,

    /// Notify when port becomes active.
    #[serde(default = "default_true", rename = "notifyOnStart")]
    pub notify_on_start: bool,

    /// Notify when port becomes inactive.
    #[serde(default = "default_true", rename = "notifyOnStop")]
    pub notify_on_stop: bool,
}

fn default_true() -> bool {
    true
}

impl From<&WatchedPort> for WatchedPortJson {
    fn from(wp: &WatchedPort) -> Self {
        Self {
            id: wp.id.to_string(),
            port: wp.port,
            notify_on_start: wp.notify_on_start,
            notify_on_stop: wp.notify_on_stop,
        }
    }
}

impl TryFrom<&WatchedPortJson> for WatchedPort {
    type Error = uuid::Error;

    fn try_from(json: &WatchedPortJson) -> std::result::Result<Self, Self::Error> {
        let id = uuid::Uuid::parse_str(&json.id)?;
        Ok(WatchedPort::with_id(
            id,
            json.port,
            json.notify_on_start,
            json.notify_on_stop,
        ))
    }
}

/// Configuration store for managing app settings.
///
/// Handles reading and writing configuration to `~/.portkiller/config.json`.
pub struct ConfigStore {
    /// Path to the configuration file.
    config_path: PathBuf,
}

impl ConfigStore {
    /// Create a new config store with the default path.
    ///
    /// Default path: `~/.portkiller/config.json`
    pub fn new() -> Result<Self> {
        let home = dirs::home_dir()
            .ok_or_else(|| Error::Config("Could not determine home directory".to_string()))?;

        let config_dir = home.join(".portkiller");
        let config_path = config_dir.join("config.json");

        Ok(Self { config_path })
    }

    /// Create a config store with a custom path (for testing).
    pub fn with_path(config_path: PathBuf) -> Self {
        Self { config_path }
    }

    /// Get the configuration directory path.
    pub fn config_dir(&self) -> PathBuf {
        self.config_path.parent().unwrap().to_path_buf()
    }

    /// Load configuration from disk.
    ///
    /// Returns default config if the file doesn't exist.
    pub async fn load(&self) -> Result<Config> {
        if !self.config_path.exists() {
            return Ok(Config::default());
        }

        let content = fs::read_to_string(&self.config_path)
            .await
            .map_err(|e| Error::Config(format!("Failed to read config: {}", e)))?;

        serde_json::from_str(&content)
            .map_err(|e| Error::Config(format!("Failed to parse config: {}", e)))
    }

    /// Save configuration to disk.
    ///
    /// Creates the config directory if it doesn't exist.
    pub async fn save(&self, config: &Config) -> Result<()> {
        // Ensure config directory exists
        let config_dir = self.config_dir();
        if !config_dir.exists() {
            fs::create_dir_all(&config_dir)
                .await
                .map_err(|e| Error::Config(format!("Failed to create config directory: {}", e)))?;
        }

        // Serialize with pretty printing
        let content = serde_json::to_string_pretty(config)
            .map_err(|e| Error::Config(format!("Failed to serialize config: {}", e)))?;

        // Write atomically by writing to temp file then renaming
        let temp_path = self.config_path.with_extension("json.tmp");

        let mut file = fs::File::create(&temp_path)
            .await
            .map_err(|e| Error::Config(format!("Failed to create temp config file: {}", e)))?;

        file.write_all(content.as_bytes())
            .await
            .map_err(|e| Error::Config(format!("Failed to write config: {}", e)))?;

        file.sync_all()
            .await
            .map_err(|e| Error::Config(format!("Failed to sync config: {}", e)))?;

        fs::rename(&temp_path, &self.config_path)
            .await
            .map_err(|e| Error::Config(format!("Failed to rename config file: {}", e)))?;

        Ok(())
    }

    /// Get the set of favorite ports.
    pub async fn get_favorites(&self) -> Result<HashSet<u16>> {
        let config = self.load().await?;
        Ok(config.favorites.into_iter().collect())
    }

    /// Set the favorite ports.
    pub async fn set_favorites(&self, favorites: &HashSet<u16>) -> Result<()> {
        let mut config = self.load().await?;
        config.favorites = favorites.iter().copied().collect();
        config.favorites.sort(); // Keep sorted for consistency
        self.save(&config).await
    }

    /// Add a port to favorites.
    pub async fn add_favorite(&self, port: u16) -> Result<()> {
        let mut favorites = self.get_favorites().await?;
        favorites.insert(port);
        self.set_favorites(&favorites).await
    }

    /// Remove a port from favorites.
    pub async fn remove_favorite(&self, port: u16) -> Result<()> {
        let mut favorites = self.get_favorites().await?;
        favorites.remove(&port);
        self.set_favorites(&favorites).await
    }

    /// Get the list of watched ports.
    pub async fn get_watched_ports(&self) -> Result<Vec<WatchedPort>> {
        let config = self.load().await?;
        config
            .watched_ports
            .iter()
            .map(|json| {
                WatchedPort::try_from(json)
                    .map_err(|e| Error::Config(format!("Invalid watched port UUID: {}", e)))
            })
            .collect()
    }

    /// Set the watched ports.
    pub async fn set_watched_ports(&self, watched: &[WatchedPort]) -> Result<()> {
        let mut config = self.load().await?;
        config.watched_ports = watched.iter().map(WatchedPortJson::from).collect();
        self.save(&config).await
    }

    /// Add a watched port.
    pub async fn add_watched_port(&self, port: u16) -> Result<WatchedPort> {
        let mut watched = self.get_watched_ports().await?;

        // Check if already watching this port
        if watched.iter().any(|w| w.port == port) {
            return Err(Error::Config(format!(
                "Port {} is already being watched",
                port
            )));
        }

        let new_watch = WatchedPort::new(port);
        watched.push(new_watch.clone());
        self.set_watched_ports(&watched).await?;

        Ok(new_watch)
    }

    /// Remove a watched port by port number.
    pub async fn remove_watched_port(&self, port: u16) -> Result<()> {
        let mut watched = self.get_watched_ports().await?;
        watched.retain(|w| w.port != port);
        self.set_watched_ports(&watched).await
    }

    /// Update notification settings for a watched port.
    pub async fn update_watched_port(
        &self,
        port: u16,
        notify_on_start: bool,
        notify_on_stop: bool,
    ) -> Result<()> {
        let mut watched = self.get_watched_ports().await?;

        if let Some(wp) = watched.iter_mut().find(|w| w.port == port) {
            wp.notify_on_start = notify_on_start;
            wp.notify_on_stop = notify_on_stop;
            self.set_watched_ports(&watched).await
        } else {
            Err(Error::Config(format!("Port {} is not being watched", port)))
        }
    }

    // =========================================================================
    // Settings
    // =========================================================================

    /// Get the refresh interval in seconds.
    pub async fn get_refresh_interval(&self) -> Result<u64> {
        let config = self.load().await?;
        Ok(config.refresh_interval)
    }

    /// Set the refresh interval in seconds.
    pub async fn set_refresh_interval(&self, interval: u64) -> Result<()> {
        let mut config = self.load().await?;
        config.refresh_interval = interval;
        self.save(&config).await
    }

    /// Get port forward auto-start setting.
    pub async fn get_port_forward_auto_start(&self) -> Result<bool> {
        let config = self.load().await?;
        Ok(config.port_forward_auto_start)
    }

    /// Set port forward auto-start setting.
    pub async fn set_port_forward_auto_start(&self, enabled: bool) -> Result<()> {
        let mut config = self.load().await?;
        config.port_forward_auto_start = enabled;
        self.save(&config).await
    }

    /// Get port forward show notifications setting.
    pub async fn get_port_forward_show_notifications(&self) -> Result<bool> {
        let config = self.load().await?;
        Ok(config.port_forward_show_notifications)
    }

    /// Set port forward show notifications setting.
    pub async fn set_port_forward_show_notifications(&self, enabled: bool) -> Result<()> {
        let mut config = self.load().await?;
        config.port_forward_show_notifications = enabled;
        self.save(&config).await
    }
}

impl Default for ConfigStore {
    fn default() -> Self {
        Self::new().expect("Failed to create config store")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    async fn test_store() -> (ConfigStore, tempfile::TempDir) {
        let dir = tempdir().unwrap();
        let path = dir.path().join("config.json");
        (ConfigStore::with_path(path), dir)
    }

    #[tokio::test]
    async fn test_load_nonexistent() {
        let (store, _dir) = test_store().await;
        let config = store.load().await.unwrap();
        assert!(config.favorites.is_empty());
        assert!(config.watched_ports.is_empty());
    }

    #[tokio::test]
    async fn test_save_and_load() {
        let (store, _dir) = test_store().await;

        let config = Config {
            favorites: vec![3000, 8080],
            watched_ports: vec![WatchedPortJson {
                id: uuid::Uuid::new_v4().to_string(),
                port: 5432,
                notify_on_start: true,
                notify_on_stop: false,
            }],
            refresh_interval: 5,
            port_forward_auto_start: true,
            port_forward_show_notifications: true,
        };

        store.save(&config).await.unwrap();

        let loaded = store.load().await.unwrap();
        assert_eq!(loaded.favorites, vec![3000, 8080]);
        assert_eq!(loaded.watched_ports.len(), 1);
        assert_eq!(loaded.watched_ports[0].port, 5432);
    }

    #[tokio::test]
    async fn test_favorites() {
        let (store, _dir) = test_store().await;

        // Add favorites
        store.add_favorite(3000).await.unwrap();
        store.add_favorite(8080).await.unwrap();

        let favorites = store.get_favorites().await.unwrap();
        assert!(favorites.contains(&3000));
        assert!(favorites.contains(&8080));

        // Remove favorite
        store.remove_favorite(3000).await.unwrap();
        let favorites = store.get_favorites().await.unwrap();
        assert!(!favorites.contains(&3000));
        assert!(favorites.contains(&8080));
    }

    #[tokio::test]
    async fn test_watched_ports() {
        let (store, _dir) = test_store().await;

        // Add watched port
        let wp = store.add_watched_port(5432).await.unwrap();
        assert_eq!(wp.port, 5432);
        assert!(wp.notify_on_start);
        assert!(wp.notify_on_stop);

        // Get watched ports
        let watched = store.get_watched_ports().await.unwrap();
        assert_eq!(watched.len(), 1);
        assert_eq!(watched[0].port, 5432);

        // Update watched port
        store.update_watched_port(5432, false, true).await.unwrap();
        let watched = store.get_watched_ports().await.unwrap();
        assert!(!watched[0].notify_on_start);
        assert!(watched[0].notify_on_stop);

        // Remove watched port
        store.remove_watched_port(5432).await.unwrap();
        let watched = store.get_watched_ports().await.unwrap();
        assert!(watched.is_empty());
    }

    #[tokio::test]
    async fn test_duplicate_watched_port() {
        let (store, _dir) = test_store().await;

        store.add_watched_port(3000).await.unwrap();
        let result = store.add_watched_port(3000).await;
        assert!(result.is_err());
    }
}
