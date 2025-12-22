//! Adapters layer - External system implementations.
//!
//! This module contains implementations of the port traits defined in `ports`.
//! Each adapter handles communication with external systems.

pub mod scanner;

// Re-export main types for convenience
pub use scanner::PortScanner;
