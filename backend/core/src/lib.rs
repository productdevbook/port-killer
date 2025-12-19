//! PortKiller Core Library
//!
//! Cross-platform library for port scanning and process management.
//! Provides functionality to:
//! - Scan listening TCP ports
//! - Kill processes by PID (gracefully or forcefully)
//! - Manage user configuration (favorites, watched ports)
//! - Central engine with auto-refresh and state management
//!
//! # Platform Support
//! - macOS: Uses `lsof` and `ps` commands
//! - Linux: Uses `ss` or `netstat` commands (planned)
//! - Windows: Uses `netstat` command (planned)

pub mod config;
pub mod engine;
pub mod error;
pub mod killer;
pub mod models;
pub mod scanner;

// Re-export commonly used types
pub use config::ConfigStore;
pub use engine::{Notification, PortKillerEngine};
pub use error::{Error, Result};
pub use killer::ProcessKiller;
pub use models::{filter_ports, PortFilter, PortInfo, ProcessType, WatchedPort};
pub use scanner::{PortScanner, Scanner};
