//! Kubernetes discovery using kubectl commands.

use std::path::PathBuf;
use std::time::Duration;

use tokio::process::Command;
use tokio::time::timeout;

use super::errors::{KubectlError, Result};
use super::models::{
    KubernetesNamespace, KubernetesService, NamespaceListResponse, ServiceListResponse,
};

/// Default paths to search for kubectl.
const KUBECTL_PATHS: &[&str] = &[
    "/opt/homebrew/bin/kubectl", // Apple Silicon
    "/usr/local/bin/kubectl",    // Intel Mac / Homebrew
    "/usr/bin/kubectl",          // System
];

/// Default paths to search for socat.
const SOCAT_PATHS: &[&str] = &[
    "/opt/homebrew/bin/socat", // Apple Silicon
    "/usr/local/bin/socat",    // Intel Mac / Homebrew
];

/// Timeout for kubectl discovery commands.
const KUBECTL_TIMEOUT: Duration = Duration::from_secs(15);

/// Kubernetes discovery service.
pub struct KubernetesDiscovery {
    kubectl_path: Option<PathBuf>,
    socat_path: Option<PathBuf>,
}

impl KubernetesDiscovery {
    /// Creates a new KubernetesDiscovery, searching for kubectl and socat.
    pub fn new() -> Self {
        Self {
            kubectl_path: find_executable(KUBECTL_PATHS),
            socat_path: find_executable(SOCAT_PATHS),
        }
    }

    /// Creates a new KubernetesDiscovery with custom paths.
    pub fn with_paths(kubectl_path: Option<PathBuf>, socat_path: Option<PathBuf>) -> Self {
        Self {
            kubectl_path,
            socat_path,
        }
    }

    /// Returns the kubectl path if found.
    pub fn kubectl_path(&self) -> Option<&PathBuf> {
        self.kubectl_path.as_ref()
    }

    /// Returns the socat path if found.
    pub fn socat_path(&self) -> Option<&PathBuf> {
        self.socat_path.as_ref()
    }

    /// Returns true if kubectl is available.
    pub fn is_kubectl_available(&self) -> bool {
        self.kubectl_path.is_some()
    }

    /// Returns true if socat is available.
    pub fn is_socat_available(&self) -> bool {
        self.socat_path.is_some()
    }

    /// Fetches all Kubernetes namespaces.
    pub async fn fetch_namespaces(&self) -> Result<Vec<KubernetesNamespace>> {
        let output = self
            .execute_kubectl(&["get", "namespaces", "-o", "json", "--request-timeout=10s"])
            .await?;

        let response: NamespaceListResponse = serde_json::from_str(&output)
            .map_err(|e| KubectlError::ParsingFailed(e.to_string()))?;

        let mut namespaces = response.into_namespaces();
        namespaces.sort_by(|a, b| a.name.cmp(&b.name));

        Ok(namespaces)
    }

    /// Fetches services in a specific namespace.
    pub async fn fetch_services(&self, namespace: &str) -> Result<Vec<KubernetesService>> {
        let output = self
            .execute_kubectl(&[
                "get",
                "services",
                "-n",
                namespace,
                "-o",
                "json",
                "--request-timeout=10s",
            ])
            .await?;

        let response: ServiceListResponse = serde_json::from_str(&output)
            .map_err(|e| KubectlError::ParsingFailed(e.to_string()))?;

        let mut services = response.into_services();
        services.sort_by(|a, b| a.name.cmp(&b.name));

        Ok(services)
    }

    /// Executes a kubectl command and returns the output.
    async fn execute_kubectl(&self, args: &[&str]) -> Result<String> {
        let kubectl_path = self
            .kubectl_path
            .as_ref()
            .ok_or(KubectlError::KubectlNotFound)?;

        let result = timeout(KUBECTL_TIMEOUT, async {
            let output = Command::new(kubectl_path).args(args).output().await?;

            Ok::<_, std::io::Error>((output.status, output.stdout, output.stderr))
        })
        .await;

        match result {
            Ok(Ok((status, stdout, stderr))) => {
                if status.success() {
                    String::from_utf8(stdout)
                        .map_err(|e| KubectlError::ParsingFailed(e.to_string()))
                } else {
                    let stderr_str = String::from_utf8_lossy(&stderr);
                    Err(KubectlError::from_kubectl_error(&stderr_str))
                }
            }
            Ok(Err(e)) => Err(KubectlError::Io(e)),
            Err(_) => Err(KubectlError::Timeout),
        }
    }
}

impl Default for KubernetesDiscovery {
    fn default() -> Self {
        Self::new()
    }
}

/// Finds an executable in the given paths.
fn find_executable(paths: &[&str]) -> Option<PathBuf> {
    for path in paths {
        let path_buf = PathBuf::from(path);
        if path_buf.exists() {
            return Some(path_buf);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kubernetes_discovery_creation() {
        let discovery = KubernetesDiscovery::new();
        // Just test that it doesn't panic
        let _ = discovery.is_kubectl_available();
        let _ = discovery.is_socat_available();
    }

    #[test]
    fn test_find_executable() {
        // Test with a path that should exist on most systems
        let result = find_executable(&["/bin/ls", "/usr/bin/ls"]);
        assert!(result.is_some());

        // Test with a path that shouldn't exist
        let result = find_executable(&["/nonexistent/path"]);
        assert!(result.is_none());
    }

    #[test]
    fn test_kubectl_error_detection() {
        let connection_refused = KubectlError::from_kubectl_error("connection refused");
        assert!(connection_refused.is_cluster_not_connected());

        let no_config = KubectlError::from_kubectl_error("no configuration has been provided");
        assert!(no_config.is_cluster_not_connected());

        let dial_error = KubectlError::from_kubectl_error("dial tcp 127.0.0.1:6443: connect");
        assert!(dial_error.is_cluster_not_connected());

        let other_error = KubectlError::from_kubectl_error("some other error");
        assert!(!other_error.is_cluster_not_connected());
    }
}
