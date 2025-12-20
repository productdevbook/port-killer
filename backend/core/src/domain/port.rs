//! Port and process domain models.

use std::collections::HashSet;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::WatchedPort;

// ============================================================================
// ProcessType
// ============================================================================

/// Category of process based on its function.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub enum ProcessType {
    /// Web servers (nginx, apache, caddy, etc.)
    WebServer,
    /// Database servers (postgres, mysql, redis, etc.)
    Database,
    /// Development tools (node, python, vite, etc.)
    Development,
    /// System processes (launchd, kernel services, etc.)
    System,
    /// Other/unknown processes
    #[default]
    Other,
}

impl ProcessType {
    /// All available process types.
    pub const ALL: [ProcessType; 5] = [
        ProcessType::WebServer,
        ProcessType::Database,
        ProcessType::Development,
        ProcessType::System,
        ProcessType::Other,
    ];

    /// Detect the process type from a process name.
    pub fn detect(process_name: &str) -> Self {
        let name = process_name.to_lowercase();

        const WEB_SERVERS: &[&str] = &[
            "nginx", "apache", "httpd", "caddy", "traefik", "lighttpd", "envoy",
        ];
        if WEB_SERVERS.iter().any(|s| name.contains(s)) {
            return ProcessType::WebServer;
        }

        const DATABASES: &[&str] = &[
            "postgres", "mysql", "mariadb", "redis", "mongo", "sqlite",
            "cockroach", "clickhouse", "cassandra", "elasticsearch", "memcached",
        ];
        if DATABASES.iter().any(|s| name.contains(s)) {
            return ProcessType::Database;
        }

        const DEV_TOOLS: &[&str] = &[
            "node", "npm", "yarn", "pnpm", "bun", "deno", "python", "ruby", "php",
            "java", "go", "cargo", "rustc", "swift", "vite", "webpack", "esbuild",
            "next", "nuxt", "remix", "astro", "turbo", "parcel",
        ];
        if DEV_TOOLS.iter().any(|s| name.contains(s)) {
            return ProcessType::Development;
        }

        const SYSTEM_PROCS: &[&str] = &[
            "launchd", "rapportd", "sharingd", "airplay", "control", "kernel",
            "mds", "spotlight", "systemd", "init", "dbus", "udev",
        ];
        if SYSTEM_PROCS.iter().any(|s| name.contains(s)) {
            return ProcessType::System;
        }

        ProcessType::Other
    }

    /// Get the display name for this process type.
    pub fn display_name(&self) -> &'static str {
        match self {
            ProcessType::WebServer => "Web Server",
            ProcessType::Database => "Database",
            ProcessType::Development => "Development",
            ProcessType::System => "System",
            ProcessType::Other => "Other",
        }
    }

    /// Get an icon identifier for this process type.
    pub fn icon(&self) -> &'static str {
        match self {
            ProcessType::WebServer => "globe",
            ProcessType::Database => "cylinder",
            ProcessType::Development => "hammer",
            ProcessType::System => "gearshape",
            ProcessType::Other => "powerplug",
        }
    }
}

impl std::fmt::Display for ProcessType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.display_name())
    }
}

// ============================================================================
// PortInfo
// ============================================================================

/// Information about a network port and its associated process.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PortInfo {
    /// Unique identifier for this port info instance.
    pub id: Uuid,
    /// The port number (e.g., 3000, 8080).
    pub port: u16,
    /// Process ID of the process using this port.
    pub pid: u32,
    /// Name of the process using this port.
    pub process_name: String,
    /// Network address the port is bound to.
    pub address: String,
    /// Username of the process owner.
    pub user: String,
    /// Full command line that started the process.
    pub command: String,
    /// File descriptor information from lsof.
    pub fd: String,
    /// Whether this port is currently active/listening.
    pub is_active: bool,
}

impl PortInfo {
    /// Create a new active port from scan results.
    pub fn active(
        port: u16,
        pid: u32,
        process_name: impl Into<String>,
        address: impl Into<String>,
        user: impl Into<String>,
        command: impl Into<String>,
        fd: impl Into<String>,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            port,
            pid,
            process_name: process_name.into(),
            address: address.into(),
            user: user.into(),
            command: command.into(),
            fd: fd.into(),
            is_active: true,
        }
    }

    /// Create an inactive placeholder for a favorited/watched port.
    pub fn inactive(port: u16) -> Self {
        Self {
            id: Uuid::new_v4(),
            port,
            pid: 0,
            process_name: "Not running".to_string(),
            address: "-".to_string(),
            user: "-".to_string(),
            command: String::new(),
            fd: String::new(),
            is_active: false,
        }
    }

    /// Get the formatted port number for display (e.g., ":3000").
    pub fn display_port(&self) -> String {
        format!(":{}", self.port)
    }

    /// Detect the process type based on the process name.
    pub fn process_type(&self) -> ProcessType {
        ProcessType::detect(&self.process_name)
    }

    /// Check if this port matches a search query.
    pub fn matches_search(&self, query: &str) -> bool {
        if query.is_empty() {
            return true;
        }
        let query_lower = query.to_lowercase();
        self.process_name.to_lowercase().contains(&query_lower)
            || self.port.to_string().contains(&query_lower)
            || self.pid.to_string().contains(&query_lower)
            || self.address.to_lowercase().contains(&query_lower)
            || self.user.to_lowercase().contains(&query_lower)
            || self.command.to_lowercase().contains(&query_lower)
    }
}

impl std::fmt::Display for PortInfo {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{}:{} (PID: {}, Process: {})",
            self.address, self.port, self.pid, self.process_name
        )
    }
}

// ============================================================================
// PortFilter
// ============================================================================

/// Filter criteria for port listings.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortFilter {
    /// Text to search across port info fields.
    #[serde(default)]
    pub search_text: String,
    /// Minimum port number (inclusive).
    #[serde(default)]
    pub min_port: Option<u16>,
    /// Maximum port number (inclusive).
    #[serde(default)]
    pub max_port: Option<u16>,
    /// Process types to include. If empty, includes all types.
    #[serde(default = "all_process_types")]
    pub process_types: HashSet<ProcessType>,
    /// Only show favorite ports.
    #[serde(default)]
    pub show_only_favorites: bool,
    /// Only show watched ports.
    #[serde(default)]
    pub show_only_watched: bool,
}

fn all_process_types() -> HashSet<ProcessType> {
    ProcessType::ALL.into_iter().collect()
}

impl Default for PortFilter {
    fn default() -> Self {
        Self {
            search_text: String::new(),
            min_port: None,
            max_port: None,
            process_types: all_process_types(),
            show_only_favorites: false,
            show_only_watched: false,
        }
    }
}

impl PortFilter {
    /// Create a new filter with default settings.
    pub fn new() -> Self {
        Self::default()
    }

    /// Check if the filter has any active conditions.
    pub fn is_active(&self) -> bool {
        !self.search_text.is_empty()
            || self.min_port.is_some()
            || self.max_port.is_some()
            || self.process_types.len() < ProcessType::ALL.len()
            || self.show_only_favorites
            || self.show_only_watched
    }

    /// Check if a port matches all filter criteria.
    pub fn matches(
        &self,
        port: &PortInfo,
        favorites: &HashSet<u16>,
        watched: &[WatchedPort],
    ) -> bool {
        if !self.search_text.is_empty() && !port.matches_search(&self.search_text) {
            return false;
        }
        if let Some(min) = self.min_port {
            if port.port < min {
                return false;
            }
        }
        if let Some(max) = self.max_port {
            if port.port > max {
                return false;
            }
        }
        if !self.process_types.is_empty() && !self.process_types.contains(&port.process_type()) {
            return false;
        }
        if self.show_only_favorites && !favorites.contains(&port.port) {
            return false;
        }
        if self.show_only_watched && !watched.iter().any(|w| w.port == port.port) {
            return false;
        }
        true
    }

    /// Reset all filter criteria to defaults.
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// Set the search text.
    pub fn with_search(mut self, text: impl Into<String>) -> Self {
        self.search_text = text.into();
        self
    }

    /// Set the port range.
    pub fn with_port_range(mut self, min: Option<u16>, max: Option<u16>) -> Self {
        self.min_port = min;
        self.max_port = max;
        self
    }

    /// Set the allowed process types.
    pub fn with_process_types(mut self, types: impl IntoIterator<Item = ProcessType>) -> Self {
        self.process_types = types.into_iter().collect();
        self
    }

    /// Enable/disable favorites-only mode.
    pub fn with_favorites_only(mut self, enabled: bool) -> Self {
        self.show_only_favorites = enabled;
        self
    }

    /// Enable/disable watched-only mode.
    pub fn with_watched_only(mut self, enabled: bool) -> Self {
        self.show_only_watched = enabled;
        self
    }
}

/// Apply a filter to a list of ports.
pub fn filter_ports(
    ports: &[PortInfo],
    filter: &PortFilter,
    favorites: &HashSet<u16>,
    watched: &[WatchedPort],
) -> Vec<PortInfo> {
    ports
        .iter()
        .filter(|p| filter.matches(p, favorites, watched))
        .cloned()
        .collect()
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_process_type_detect() {
        assert_eq!(ProcessType::detect("nginx"), ProcessType::WebServer);
        assert_eq!(ProcessType::detect("postgres"), ProcessType::Database);
        assert_eq!(ProcessType::detect("node"), ProcessType::Development);
        assert_eq!(ProcessType::detect("launchd"), ProcessType::System);
        assert_eq!(ProcessType::detect("unknown"), ProcessType::Other);
    }

    #[test]
    fn test_port_info_active() {
        let port = PortInfo::active(3000, 1234, "node", "*", "user", "node server.js", "19u");
        assert!(port.is_active);
        assert_eq!(port.port, 3000);
        assert_eq!(port.process_type(), ProcessType::Development);
    }

    #[test]
    fn test_port_filter_default() {
        let filter = PortFilter::new();
        assert!(!filter.is_active());
    }

    #[test]
    fn test_filter_ports() {
        let ports = vec![
            PortInfo::active(3000, 1, "node", "*", "user", "node", "1u"),
            PortInfo::active(80, 2, "nginx", "*", "root", "nginx", "2u"),
        ];
        let filter = PortFilter::new().with_search("node");
        let result = filter_ports(&ports, &filter, &HashSet::new(), &[]);
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].port, 3000);
    }
}
