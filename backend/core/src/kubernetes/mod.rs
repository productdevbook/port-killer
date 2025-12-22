//! Kubernetes module for port forwarding and service discovery.
//!
//! This module provides:
//! - Service and namespace discovery via kubectl
//! - Port forward connection configuration and persistence
//! - Process management for kubectl port-forward and socat
//! - Connection monitoring and auto-reconnect

pub mod config_store;
pub mod connection_manager;
pub mod discovery;
pub mod errors;
pub mod models;
pub mod process_manager;

// Re-export commonly used types
pub use config_store::KubernetesConfigStore;
pub use connection_manager::KubernetesConnectionManager;
pub use discovery::KubernetesDiscovery;
pub use errors::{KubectlError, Result};
pub use models::{
    KubernetesConfig, KubernetesNamespace, KubernetesService, PortForwardConnectionConfig,
    PortForwardConnectionState, PortForwardNotification, PortForwardProcessType, PortForwardStatus,
    ServicePort,
};
pub use process_manager::PortForwardProcessManager;
