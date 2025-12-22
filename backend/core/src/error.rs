//! Error types for the portkiller-core library.

use thiserror::Error;

use crate::kubernetes::errors::KubectlError;

/// Result type alias for portkiller operations.
pub type Result<T> = std::result::Result<T, Error>;

/// Errors that can occur during port scanning and process management.
#[derive(Error, Debug)]
pub enum Error {
    /// Failed to execute a system command.
    #[error("Command execution failed: {0}")]
    CommandFailed(String),

    /// Failed to parse command output.
    #[error("Failed to parse output: {0}")]
    ParseError(String),

    /// Failed to kill a process.
    #[error("Failed to kill process {pid}: {reason}")]
    KillFailed { pid: u32, reason: String },

    /// Permission denied for an operation.
    #[error("Permission denied: {0}")]
    PermissionDenied(String),

    /// I/O error.
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    /// JSON serialization/deserialization error.
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    /// Configuration error.
    #[error("Configuration error: {0}")]
    Config(String),

    /// Platform not supported.
    #[error("Platform not supported: {0}")]
    UnsupportedPlatform(String),

    /// Kubernetes/kubectl error.
    #[error("Kubernetes error: {0}")]
    Kubernetes(#[from] KubectlError),
}
