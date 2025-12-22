//! Kubernetes-specific error types.

use thiserror::Error;

/// Errors that can occur during kubectl operations.
#[derive(Error, Debug)]
pub enum KubectlError {
    #[error("kubectl not found. Install it with: brew install kubernetes-cli")]
    KubectlNotFound,

    #[error("socat not found. Install it with: brew install socat")]
    SocatNotFound,

    #[error("Kubernetes cluster not connected. Check your kubeconfig.")]
    ClusterNotConnected,

    #[error("kubectl execution failed: {0}")]
    ExecutionFailed(String),

    #[error("kubectl execution timed out")]
    Timeout,

    #[error("Failed to parse kubectl output: {0}")]
    ParsingFailed(String),

    #[error("Connection not found: {0}")]
    ConnectionNotFound(String),

    #[error("Port conflict: port {0} is already in use")]
    PortConflict(u16),

    #[error("Process management error: {0}")]
    ProcessError(String),

    #[error("Configuration error: {0}")]
    ConfigError(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

impl KubectlError {
    /// Returns true if this error indicates the cluster is not connected.
    pub fn is_cluster_not_connected(&self) -> bool {
        matches!(self, Self::ClusterNotConnected)
    }

    /// Returns true if this error is a timeout.
    pub fn is_timeout(&self) -> bool {
        matches!(self, Self::Timeout)
    }

    /// Detects cluster connection errors from kubectl stderr output.
    pub fn from_kubectl_error(stderr: &str) -> Self {
        let stderr_lower = stderr.to_lowercase();
        if stderr_lower.contains("unable to connect")
            || stderr_lower.contains("connection refused")
            || stderr_lower.contains("no configuration")
            || stderr_lower.contains("dial tcp")
            || stderr_lower.contains("couldn't get current server api")
            || stderr_lower.contains("the connection to the server")
        {
            Self::ClusterNotConnected
        } else {
            Self::ExecutionFailed(stderr.trim().to_string())
        }
    }
}

pub type Result<T> = std::result::Result<T, KubectlError>;
