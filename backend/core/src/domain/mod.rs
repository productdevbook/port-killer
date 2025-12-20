//! Domain layer - Pure business logic and data models.
//!
//! This module contains domain entities that represent core business concepts.
//! These types have no I/O dependencies and can be tested in isolation.

mod port;
mod watched;

// Re-export all domain types
pub use port::{filter_ports, PortFilter, PortInfo, ProcessType};
pub use watched::WatchedPort;
