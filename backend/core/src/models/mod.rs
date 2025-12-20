//! Data models for port and process information.
//!
//! NOTE: This module re-exports types from `domain` for backwards compatibility.
//! New code should import directly from `crate::domain`.

// Re-export from domain layer
pub use crate::domain::{filter_ports, PortFilter, PortInfo, ProcessType, WatchedPort};
