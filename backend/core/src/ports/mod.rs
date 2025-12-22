//! Ports layer - Trait definitions (interfaces).
//!
//! This module defines the interfaces that the application layer uses
//! to interact with external systems. Implementations live in `adapters`.

mod config;
mod killer;
mod scanner;

pub use config::ConfigRepository;
pub use killer::ProcessKillerPort;
pub use scanner::PortScannerPort;
