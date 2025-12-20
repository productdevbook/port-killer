//! Port information data structure.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::ProcessType;

/// Information about a network port and its associated process.
///
/// PortInfo encapsulates all details about a listening network port, including
/// the process that owns it, the address it's bound to, and whether it's currently active.
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

    /// Network address the port is bound to (e.g., "*", "127.0.0.1", "::1").
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
    ///
    /// Searches across process name, port number, PID, address, user, and command.
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_active_port() {
        let port = PortInfo::active(
            3000,
            1234,
            "node",
            "127.0.0.1",
            "user",
            "node server.js",
            "19u",
        );
        assert!(port.is_active);
        assert_eq!(port.port, 3000);
        assert_eq!(port.pid, 1234);
        assert_eq!(port.process_name, "node");
    }

    #[test]
    fn test_inactive_port() {
        let port = PortInfo::inactive(8080);
        assert!(!port.is_active);
        assert_eq!(port.port, 8080);
        assert_eq!(port.pid, 0);
        assert_eq!(port.process_name, "Not running");
    }

    #[test]
    fn test_display_port() {
        let port = PortInfo::inactive(3000);
        assert_eq!(port.display_port(), ":3000");
    }

    #[test]
    fn test_process_type() {
        let node_port = PortInfo::active(3000, 1234, "node", "*", "user", "node", "19u");
        assert_eq!(node_port.process_type(), ProcessType::Development);

        let nginx_port = PortInfo::active(80, 1, "nginx", "*", "root", "nginx", "6u");
        assert_eq!(nginx_port.process_type(), ProcessType::WebServer);
    }

    #[test]
    fn test_matches_search() {
        let port = PortInfo::active(
            3000,
            1234,
            "node",
            "127.0.0.1",
            "testuser",
            "node server.js",
            "19u",
        );

        assert!(port.matches_search("node"));
        assert!(port.matches_search("3000"));
        assert!(port.matches_search("1234"));
        assert!(port.matches_search("127.0.0.1"));
        assert!(port.matches_search("testuser"));
        assert!(port.matches_search("server.js"));
        assert!(port.matches_search("")); // Empty query matches all
        assert!(!port.matches_search("nginx")); // Non-matching query
    }
}
