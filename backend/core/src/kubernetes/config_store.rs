//! Kubernetes configuration persistence.
//!
//! Stores port forward connections in `~/.portkiller/kubernetes.json`.

use std::path::PathBuf;

use tokio::fs;
use uuid::Uuid;

use super::errors::{KubectlError, Result};
use super::models::{KubernetesConfig, PortForwardConnectionConfig};

/// Configuration store for Kubernetes port forward connections.
pub struct KubernetesConfigStore {
    config_path: PathBuf,
}

impl KubernetesConfigStore {
    /// Creates a new config store with the default path (~/.portkiller/kubernetes.json).
    pub fn new() -> Result<Self> {
        let config_dir = dirs::home_dir()
            .ok_or_else(|| KubectlError::ConfigError("Could not find home directory".to_string()))?
            .join(".portkiller");

        Ok(Self {
            config_path: config_dir.join("kubernetes.json"),
        })
    }

    /// Creates a new config store with a custom path.
    pub fn with_path(path: PathBuf) -> Self {
        Self { config_path: path }
    }

    /// Returns the config file path.
    pub fn config_path(&self) -> &PathBuf {
        &self.config_path
    }

    /// Loads the configuration from disk.
    pub async fn load(&self) -> Result<KubernetesConfig> {
        if !self.config_path.exists() {
            return Ok(KubernetesConfig::default());
        }

        let content = fs::read_to_string(&self.config_path)
            .await
            .map_err(|e| KubectlError::ConfigError(format!("Failed to read config: {}", e)))?;

        serde_json::from_str(&content)
            .map_err(|e| KubectlError::ConfigError(format!("Failed to parse config: {}", e)))
    }

    /// Saves the configuration to disk.
    pub async fn save(&self, config: &KubernetesConfig) -> Result<()> {
        // Ensure the directory exists
        if let Some(parent) = self.config_path.parent() {
            fs::create_dir_all(parent).await.map_err(|e| {
                KubectlError::ConfigError(format!("Failed to create config dir: {}", e))
            })?;
        }

        // Write to a temp file first, then rename (atomic write)
        let temp_path = self.config_path.with_extension("json.tmp");
        let content = serde_json::to_string_pretty(config)
            .map_err(|e| KubectlError::ConfigError(format!("Failed to serialize config: {}", e)))?;

        fs::write(&temp_path, content)
            .await
            .map_err(|e| KubectlError::ConfigError(format!("Failed to write config: {}", e)))?;

        fs::rename(&temp_path, &self.config_path)
            .await
            .map_err(|e| KubectlError::ConfigError(format!("Failed to save config: {}", e)))?;

        Ok(())
    }

    /// Gets all port forward connections.
    pub async fn get_connections(&self) -> Result<Vec<PortForwardConnectionConfig>> {
        let config = self.load().await?;
        Ok(config.connections)
    }

    /// Gets a single connection by ID.
    pub async fn get_connection(&self, id: Uuid) -> Result<Option<PortForwardConnectionConfig>> {
        let config = self.load().await?;
        Ok(config.connections.into_iter().find(|c| c.id == id))
    }

    /// Adds a new port forward connection.
    pub async fn add_connection(&self, connection: PortForwardConnectionConfig) -> Result<()> {
        let mut config = self.load().await?;

        // Check for duplicate
        if config.connections.iter().any(|c| c.id == connection.id) {
            return Err(KubectlError::ConfigError(format!(
                "Connection with ID {} already exists",
                connection.id
            )));
        }

        config.connections.push(connection);
        self.save(&config).await
    }

    /// Removes a port forward connection by ID.
    pub async fn remove_connection(&self, id: Uuid) -> Result<()> {
        let mut config = self.load().await?;
        let original_len = config.connections.len();

        config.connections.retain(|c| c.id != id);

        if config.connections.len() == original_len {
            return Err(KubectlError::ConnectionNotFound(id.to_string()));
        }

        self.save(&config).await
    }

    /// Updates an existing port forward connection.
    pub async fn update_connection(&self, connection: PortForwardConnectionConfig) -> Result<()> {
        let mut config = self.load().await?;

        let Some(existing) = config
            .connections
            .iter_mut()
            .find(|c| c.id == connection.id)
        else {
            return Err(KubectlError::ConnectionNotFound(connection.id.to_string()));
        };

        *existing = connection;
        self.save(&config).await
    }

    /// Clears all connections.
    pub async fn clear(&self) -> Result<()> {
        self.save(&KubernetesConfig::default()).await
    }
}

impl Default for KubernetesConfigStore {
    fn default() -> Self {
        Self::new().expect("Failed to create KubernetesConfigStore")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_config_store_crud() {
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("kubernetes.json");
        let store = KubernetesConfigStore::with_path(config_path);

        // Initially empty
        let connections = store.get_connections().await.unwrap();
        assert!(connections.is_empty());

        // Add a connection
        let conn = PortForwardConnectionConfig::new(
            "test".to_string(),
            "default".to_string(),
            "my-service".to_string(),
            8080,
            80,
        );
        let conn_id = conn.id;
        store.add_connection(conn).await.unwrap();

        // Verify it was added
        let connections = store.get_connections().await.unwrap();
        assert_eq!(connections.len(), 1);
        assert_eq!(connections[0].name, "test");

        // Get by ID
        let conn = store.get_connection(conn_id).await.unwrap();
        assert!(conn.is_some());

        // Update
        let mut updated = conn.unwrap();
        updated.name = "updated".to_string();
        store.update_connection(updated).await.unwrap();

        let conn = store.get_connection(conn_id).await.unwrap().unwrap();
        assert_eq!(conn.name, "updated");

        // Remove
        store.remove_connection(conn_id).await.unwrap();
        let connections = store.get_connections().await.unwrap();
        assert!(connections.is_empty());
    }

    #[tokio::test]
    async fn test_config_store_duplicate_prevention() {
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("kubernetes.json");
        let store = KubernetesConfigStore::with_path(config_path);

        let conn = PortForwardConnectionConfig::new(
            "test".to_string(),
            "default".to_string(),
            "my-service".to_string(),
            8080,
            80,
        );

        // First add should succeed
        store.add_connection(conn.clone()).await.unwrap();

        // Second add with same ID should fail
        let result = store.add_connection(conn).await;
        assert!(result.is_err());
    }
}
