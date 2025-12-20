//! Application layer - Use case services.
//!
//! This module contains application services that orchestrate
//! domain logic and adapter interactions.
//!
//! Services are designed to be thin orchestrators that:
//! - Accept domain types as inputs
//! - Use ports (traits) for external dependencies
//! - Return domain types as outputs
//!
//! # Migration Note
//! These services are being introduced incrementally.
//! The `engine` module still contains the main orchestration logic
//! and will gradually delegate to these services.

mod port_service;

pub use port_service::PortService;
