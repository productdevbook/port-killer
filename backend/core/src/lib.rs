//! PortKiller Core Library
//!
//! Cross-platform library for port scanning and process management.
//! Provides functionality to:
//! - Scan listening TCP ports
//! - Kill processes by PID (gracefully or forcefully)
//! - Manage user configuration (favorites, watched ports)
//! - Central engine with auto-refresh and state management
//!
//! # Architecture
//! This library follows hexagonal architecture (ports & adapters):
//! - `domain`: Pure business logic and data models
//! - `ports`: Trait definitions (interfaces)
//! - `adapters`: External system implementations
//! - `application`: Use case services
//!
//! # Platform Support
//! - macOS: Uses `lsof` and `ps` commands
//! - Linux: Uses `ss` or `netstat` commands
//! - Windows: Uses `netstat` command (planned)

// Hexagonal architecture layers
pub mod domain;
pub mod ports;
pub mod adapters;

// Legacy modules (will be migrated to adapters)
pub mod config;
pub mod engine;
pub mod error;
pub mod killer;
pub mod kubernetes;
pub mod models;
pub mod scanner;

// Re-export domain types (primary API)
pub use domain::{filter_ports, PortFilter, PortInfo, ProcessType, WatchedPort};

// Re-export other commonly used types
pub use config::ConfigStore;
pub use engine::{Notification, PortKillerEngine};
pub use error::{Error, Result};
pub use killer::ProcessKiller;
pub use scanner::{PortScanner, Scanner};
