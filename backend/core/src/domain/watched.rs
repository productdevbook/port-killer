//! Watched port domain model.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// A port being monitored for status changes.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct WatchedPort {
    /// Unique identifier for this watched port.
    #[serde(default = "Uuid::new_v4")]
    pub id: Uuid,
    /// The port number being watched.
    pub port: u16,
    /// Whether to send a notification when this port becomes active.
    #[serde(default = "default_true")]
    pub notify_on_start: bool,
    /// Whether to send a notification when this port becomes inactive.
    #[serde(default = "default_true")]
    pub notify_on_stop: bool,
}

fn default_true() -> bool {
    true
}

impl WatchedPort {
    /// Create a new watched port with default notification settings (both enabled).
    pub fn new(port: u16) -> Self {
        Self {
            id: Uuid::new_v4(),
            port,
            notify_on_start: true,
            notify_on_stop: true,
        }
    }

    /// Create a watched port with custom notification settings.
    pub fn with_notifications(port: u16, notify_on_start: bool, notify_on_stop: bool) -> Self {
        Self {
            id: Uuid::new_v4(),
            port,
            notify_on_start,
            notify_on_stop,
        }
    }

    /// Create a watched port from an existing ID.
    pub fn with_id(id: Uuid, port: u16, notify_on_start: bool, notify_on_stop: bool) -> Self {
        Self {
            id,
            port,
            notify_on_start,
            notify_on_stop,
        }
    }
}

impl std::fmt::Display for WatchedPort {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let start = if self.notify_on_start { "start" } else { "" };
        let stop = if self.notify_on_stop { "stop" } else { "" };
        let notifications = [start, stop]
            .iter()
            .filter(|s| !s.is_empty())
            .copied()
            .collect::<Vec<_>>()
            .join(", ");

        if notifications.is_empty() {
            write!(f, "Port {} (no notifications)", self.port)
        } else {
            write!(f, "Port {} (notify: {})", self.port, notifications)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_watched_port() {
        let wp = WatchedPort::new(3000);
        assert_eq!(wp.port, 3000);
        assert!(wp.notify_on_start);
        assert!(wp.notify_on_stop);
    }

    #[test]
    fn test_with_notifications() {
        let wp = WatchedPort::with_notifications(8080, true, false);
        assert_eq!(wp.port, 8080);
        assert!(wp.notify_on_start);
        assert!(!wp.notify_on_stop);
    }

    #[test]
    fn test_display() {
        let wp = WatchedPort::new(3000);
        assert_eq!(wp.to_string(), "Port 3000 (notify: start, stop)");
    }
}
