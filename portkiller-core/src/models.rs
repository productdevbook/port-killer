//! Core data models for PortKiller
//!
//! These models are platform-agnostic and used across all platforms.

use serde::{Deserialize, Serialize};

/// Information about a listening port and its associated process
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortInfo {
    /// The port number
    pub port: u16,

    /// Process ID
    pub pid: u32,

    /// Short process name (e.g., "node", "python")
    pub process_name: String,

    /// Full command line
    pub command: String,

    /// Listening address (e.g., "127.0.0.1", "*", "::1")
    pub address: String,

    /// Categorized process type
    pub process_type: ProcessType,

    /// Whether the port is currently active/listening
    pub is_active: bool,
}

impl PortInfo {
    /// Create a new PortInfo
    pub fn new(
        port: u16,
        pid: u32,
        process_name: String,
        command: String,
        address: String,
    ) -> Self {
        let process_type = ProcessType::detect(&process_name, &command);
        Self {
            port,
            pid,
            process_name,
            command,
            address,
            process_type,
            is_active: true,
        }
    }

    /// Create with explicit process type
    pub fn with_type(
        port: u16,
        pid: u32,
        process_name: String,
        command: String,
        address: String,
        process_type: ProcessType,
    ) -> Self {
        Self {
            port,
            pid,
            process_name,
            command,
            address,
            process_type,
            is_active: true,
        }
    }
}

/// Categorization of process types for filtering and display
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[repr(u8)]
pub enum ProcessType {
    /// Web servers: nginx, apache, caddy, etc.
    WebServer = 0,
    /// Databases: postgres, mysql, redis, mongo, etc.
    Database = 1,
    /// Development tools: node, python, cargo, vite, etc.
    Development = 2,
    /// System processes: launchd, kernel, etc.
    System = 3,
    /// Everything else
    #[default]
    Other = 4,
}

impl ProcessType {
    /// Detect process type from process name and command
    pub fn detect(process_name: &str, command: &str) -> Self {
        let name_lower = process_name.to_lowercase();
        let cmd_lower = command.to_lowercase();

        // Check both name and command for patterns
        let check = |pattern: &str| name_lower.contains(pattern) || cmd_lower.contains(pattern);

        // Web servers
        if check("nginx")
            || check("apache")
            || check("httpd")
            || check("caddy")
            || check("traefik")
            || check("lighttpd")
            || check("haproxy")
        {
            return ProcessType::WebServer;
        }

        // Databases
        if check("postgres")
            || check("mysql")
            || check("mariadb")
            || check("redis")
            || check("mongo")
            || check("sqlite")
            || check("cockroach")
            || check("clickhouse")
            || check("cassandra")
            || check("elasticsearch")
            || check("memcached")
        {
            return ProcessType::Database;
        }

        // Development tools
        if check("node")
            || check("npm")
            || check("yarn")
            || check("pnpm")
            || check("bun")
            || check("deno")
            || check("python")
            || check("ruby")
            || check("php")
            || check("java")
            || check("kotlin")
            || check("scala")
            || check("go")
            || check("cargo")
            || check("rustc")
            || check("swift")
            || check("dotnet")
            || check("vite")
            || check("webpack")
            || check("esbuild")
            || check("next")
            || check("nuxt")
            || check("remix")
            || check("turbo")
            || check("expo")
            || check("flutter")
        {
            return ProcessType::Development;
        }

        // System processes (macOS)
        if check("launchd")
            || check("rapportd")
            || check("sharingd")
            || check("airplay")
            || check("control")
            || check("kernel")
            || check("mds")
            || check("spotlight")
            || check("coreaudio")
            || check("windowserver")
        {
            return ProcessType::System;
        }

        // System processes (Windows)
        if check("svchost")
            || check("system")
            || check("lsass")
            || check("csrss")
            || check("services")
            || check("wininit")
            || check("smss")
        {
            return ProcessType::System;
        }

        ProcessType::Other
    }

    /// Get display name for the process type
    pub fn display_name(&self) -> &'static str {
        match self {
            ProcessType::WebServer => "Web Server",
            ProcessType::Database => "Database",
            ProcessType::Development => "Development",
            ProcessType::System => "System",
            ProcessType::Other => "Other",
        }
    }

    /// Get icon name for the process type
    pub fn icon_name(&self) -> &'static str {
        match self {
            ProcessType::WebServer => "globe",
            ProcessType::Database => "cylinder",
            ProcessType::Development => "hammer",
            ProcessType::System => "gearshape",
            ProcessType::Other => "questionmark.circle",
        }
    }
}

impl From<u8> for ProcessType {
    fn from(value: u8) -> Self {
        match value {
            0 => ProcessType::WebServer,
            1 => ProcessType::Database,
            2 => ProcessType::Development,
            3 => ProcessType::System,
            _ => ProcessType::Other,
        }
    }
}

impl From<ProcessType> for u8 {
    fn from(value: ProcessType) -> Self {
        value as u8
    }
}

/// Filter criteria for ports
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PortFilter {
    /// Text search (matches port, process name, command)
    pub search_text: Option<String>,

    /// Filter by process type
    pub process_type: Option<ProcessType>,

    /// Only show ports in this range
    pub port_range: Option<(u16, u16)>,

    /// Only show favorite ports
    pub favorites_only: bool,
}

impl PortFilter {
    /// Check if a port matches this filter
    pub fn matches(&self, port: &PortInfo, favorites: &[u16]) -> bool {
        // Search text filter
        if let Some(ref text) = self.search_text {
            let text_lower = text.to_lowercase();
            let port_str = port.port.to_string();
            if !port_str.contains(&text_lower)
                && !port.process_name.to_lowercase().contains(&text_lower)
                && !port.command.to_lowercase().contains(&text_lower)
            {
                return false;
            }
        }

        // Process type filter
        if let Some(ref ptype) = self.process_type {
            if port.process_type != *ptype {
                return false;
            }
        }

        // Port range filter
        if let Some((min, max)) = self.port_range {
            if port.port < min || port.port > max {
                return false;
            }
        }

        // Favorites filter
        if self.favorites_only && !favorites.contains(&port.port) {
            return false;
        }

        true
    }
}

/// A watched port configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WatchedPort {
    /// The port number to watch
    pub port: u16,

    /// Whether to send notifications when status changes
    pub notify_on_change: bool,

    /// Last known state
    pub last_active: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_process_type_detection() {
        assert_eq!(
            ProcessType::detect("nginx", "nginx -g daemon off"),
            ProcessType::WebServer
        );
        assert_eq!(
            ProcessType::detect("postgres", "/usr/bin/postgres"),
            ProcessType::Database
        );
        assert_eq!(
            ProcessType::detect("node", "node server.js"),
            ProcessType::Development
        );
        assert_eq!(
            ProcessType::detect("launchd", "/sbin/launchd"),
            ProcessType::System
        );
        assert_eq!(
            ProcessType::detect("unknown", "some random process"),
            ProcessType::Other
        );
    }

    #[test]
    fn test_port_filter() {
        let port = PortInfo::new(
            3000,
            1234,
            "node".to_string(),
            "node server.js".to_string(),
            "127.0.0.1".to_string(),
        );

        let filter = PortFilter {
            search_text: Some("node".to_string()),
            ..Default::default()
        };
        assert!(filter.matches(&port, &[]));

        let filter = PortFilter {
            search_text: Some("python".to_string()),
            ..Default::default()
        };
        assert!(!filter.matches(&port, &[]));

        let filter = PortFilter {
            process_type: Some(ProcessType::Development),
            ..Default::default()
        };
        assert!(filter.matches(&port, &[]));
    }

    #[test]
    fn test_process_type_conversion() {
        assert_eq!(u8::from(ProcessType::WebServer), 0);
        assert_eq!(u8::from(ProcessType::Database), 1);
        assert_eq!(ProcessType::from(0u8), ProcessType::WebServer);
        assert_eq!(ProcessType::from(255u8), ProcessType::Other);
    }
}
