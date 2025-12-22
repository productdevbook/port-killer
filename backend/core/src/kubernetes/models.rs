//! Kubernetes data models for namespace, service, and port forward configuration.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ============================================================================
// Kubernetes Discovery Models
// ============================================================================

/// A Kubernetes namespace.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct KubernetesNamespace {
    pub name: String,
}

/// A port exposed by a Kubernetes service.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ServicePort {
    pub name: Option<String>,
    pub port: u16,
    pub target_port: u16,
    pub protocol: Option<String>,
}

impl ServicePort {
    /// Returns a display name for the port (e.g., "8080 (http)").
    pub fn display_name(&self) -> String {
        match &self.name {
            Some(name) if !name.is_empty() => format!("{} ({})", self.port, name),
            _ => self.port.to_string(),
        }
    }
}

/// A Kubernetes service.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KubernetesService {
    pub name: String,
    pub namespace: String,
    pub service_type: String,
    pub cluster_ip: Option<String>,
    pub ports: Vec<ServicePort>,
}

impl KubernetesService {
    /// Returns the service ID in the format "namespace/name".
    pub fn id(&self) -> String {
        format!("{}/{}", self.namespace, self.name)
    }
}

// ============================================================================
// kubectl JSON Response Parsing
// ============================================================================

/// Response structure for `kubectl get namespaces -o json`.
#[derive(Debug, Deserialize)]
pub struct NamespaceListResponse {
    pub items: Vec<NamespaceItem>,
}

#[derive(Debug, Deserialize)]
pub struct NamespaceItem {
    pub metadata: NamespaceMetadata,
}

#[derive(Debug, Deserialize)]
pub struct NamespaceMetadata {
    pub name: String,
}

impl NamespaceListResponse {
    /// Converts the kubectl response to a list of KubernetesNamespace.
    pub fn into_namespaces(self) -> Vec<KubernetesNamespace> {
        self.items
            .into_iter()
            .map(|item| KubernetesNamespace {
                name: item.metadata.name,
            })
            .collect()
    }
}

/// Response structure for `kubectl get services -o json`.
#[derive(Debug, Deserialize)]
pub struct ServiceListResponse {
    pub items: Vec<ServiceItem>,
}

#[derive(Debug, Deserialize)]
pub struct ServiceItem {
    pub metadata: ServiceMetadata,
    pub spec: ServiceSpec,
}

#[derive(Debug, Deserialize)]
pub struct ServiceMetadata {
    pub name: String,
    pub namespace: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ServiceSpec {
    #[serde(rename = "type")]
    pub service_type: Option<String>,
    pub cluster_ip: Option<String>,
    pub ports: Option<Vec<ServicePortSpec>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ServicePortSpec {
    pub name: Option<String>,
    pub port: u16,
    pub target_port: Option<TargetPort>,
    pub protocol: Option<String>,
}

/// Kubernetes targetPort can be either an integer or a string (named port).
#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub enum TargetPort {
    Int(u16),
    String(String),
}

impl TargetPort {
    /// Returns the integer value if available.
    pub fn as_int(&self) -> Option<u16> {
        match self {
            TargetPort::Int(v) => Some(*v),
            TargetPort::String(_) => None,
        }
    }
}

impl ServiceListResponse {
    /// Converts the kubectl response to a list of KubernetesService.
    pub fn into_services(self) -> Vec<KubernetesService> {
        self.items
            .into_iter()
            .map(|item| KubernetesService {
                name: item.metadata.name,
                namespace: item.metadata.namespace,
                service_type: item
                    .spec
                    .service_type
                    .unwrap_or_else(|| "ClusterIP".to_string()),
                cluster_ip: item.spec.cluster_ip,
                ports: item
                    .spec
                    .ports
                    .unwrap_or_default()
                    .into_iter()
                    .map(|p| ServicePort {
                        name: p.name,
                        port: p.port,
                        target_port: p.target_port.and_then(|tp| tp.as_int()).unwrap_or(p.port),
                        protocol: p.protocol,
                    })
                    .collect(),
            })
            .collect()
    }
}

// ============================================================================
// Port Forward Configuration
// ============================================================================

/// Configuration for a Kubernetes port-forward connection.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PortForwardConnectionConfig {
    pub id: Uuid,
    pub name: String,
    pub namespace: String,
    pub service: String,
    pub local_port: u16,
    pub remote_port: u16,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub proxy_port: Option<u16>,
    pub is_enabled: bool,
    pub auto_reconnect: bool,
    /// Direct exec mode: Uses kubectl exec + socat for true multi-connection support.
    pub use_direct_exec: bool,
    /// Notification settings.
    pub notify_on_connect: bool,
    pub notify_on_disconnect: bool,
}

impl PortForwardConnectionConfig {
    /// Creates a new port forward configuration with default settings.
    pub fn new(
        name: String,
        namespace: String,
        service: String,
        local_port: u16,
        remote_port: u16,
    ) -> Self {
        Self {
            id: Uuid::new_v4(),
            name,
            namespace,
            service,
            local_port,
            remote_port,
            proxy_port: None,
            is_enabled: true,
            auto_reconnect: true,
            use_direct_exec: true,
            notify_on_connect: true,
            notify_on_disconnect: true,
        }
    }

    /// Returns the effective port that clients should connect to.
    pub fn effective_port(&self) -> u16 {
        self.proxy_port.unwrap_or(self.local_port)
    }
}

// ============================================================================
// Port Forward Status & State
// ============================================================================

/// Status of a port-forward process.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PortForwardStatus {
    #[default]
    Disconnected,
    Connecting,
    Connected,
    Error,
}

impl PortForwardStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Disconnected => "disconnected",
            Self::Connecting => "connecting",
            Self::Connected => "connected",
            Self::Error => "error",
        }
    }
}

/// Type of port-forward process.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PortForwardProcessType {
    /// kubectl port-forward process
    PortForward,
    /// socat proxy process
    Proxy,
}

/// Runtime state for a port-forward connection (not persisted).
#[derive(Debug, Clone)]
pub struct PortForwardConnectionState {
    pub id: Uuid,
    pub port_forward_status: PortForwardStatus,
    pub proxy_status: PortForwardStatus,
    pub last_error: Option<String>,
    /// Whether the connection was stopped intentionally by the user.
    pub is_intentionally_stopped: bool,
}

impl PortForwardConnectionState {
    /// Creates a new disconnected state.
    pub fn new(id: Uuid) -> Self {
        Self {
            id,
            port_forward_status: PortForwardStatus::Disconnected,
            proxy_status: PortForwardStatus::Disconnected,
            last_error: None,
            is_intentionally_stopped: false,
        }
    }

    /// Whether the connection is fully established (port-forward + optional proxy).
    pub fn is_fully_connected(&self, has_proxy: bool) -> bool {
        if has_proxy {
            self.port_forward_status == PortForwardStatus::Connected
                && self.proxy_status == PortForwardStatus::Connected
        } else {
            self.port_forward_status == PortForwardStatus::Connected
        }
    }
}

// ============================================================================
// Notifications
// ============================================================================

/// Notification types for port-forward events.
#[derive(Debug, Clone)]
pub enum PortForwardNotification {
    Connected {
        connection_id: Uuid,
        connection_name: String,
    },
    Disconnected {
        connection_id: Uuid,
        connection_name: String,
    },
    Error {
        connection_id: Uuid,
        connection_name: String,
        message: String,
    },
}

impl PortForwardNotification {
    pub fn notification_type(&self) -> &'static str {
        match self {
            Self::Connected { .. } => "connected",
            Self::Disconnected { .. } => "disconnected",
            Self::Error { .. } => "error",
        }
    }

    pub fn connection_id(&self) -> Uuid {
        match self {
            Self::Connected { connection_id, .. }
            | Self::Disconnected { connection_id, .. }
            | Self::Error { connection_id, .. } => *connection_id,
        }
    }

    pub fn connection_name(&self) -> &str {
        match self {
            Self::Connected {
                connection_name, ..
            }
            | Self::Disconnected {
                connection_name, ..
            }
            | Self::Error {
                connection_name, ..
            } => connection_name,
        }
    }
}

// ============================================================================
// Kubernetes Config (Persistence)
// ============================================================================

/// Full Kubernetes configuration for persistence.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KubernetesConfig {
    pub connections: Vec<PortForwardConnectionConfig>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_service_port_display_name() {
        let port_with_name = ServicePort {
            name: Some("http".to_string()),
            port: 8080,
            target_port: 80,
            protocol: Some("TCP".to_string()),
        };
        assert_eq!(port_with_name.display_name(), "8080 (http)");

        let port_without_name = ServicePort {
            name: None,
            port: 3000,
            target_port: 3000,
            protocol: None,
        };
        assert_eq!(port_without_name.display_name(), "3000");
    }

    #[test]
    fn test_kubernetes_service_id() {
        let service = KubernetesService {
            name: "my-service".to_string(),
            namespace: "default".to_string(),
            service_type: "ClusterIP".to_string(),
            cluster_ip: Some("10.0.0.1".to_string()),
            ports: vec![],
        };
        assert_eq!(service.id(), "default/my-service");
    }

    #[test]
    fn test_port_forward_config_effective_port() {
        let mut config = PortForwardConnectionConfig::new(
            "test".to_string(),
            "default".to_string(),
            "my-service".to_string(),
            8080,
            80,
        );
        assert_eq!(config.effective_port(), 8080);

        config.proxy_port = Some(9090);
        assert_eq!(config.effective_port(), 9090);
    }

    #[test]
    fn test_target_port_parsing() {
        let int_port = TargetPort::Int(8080);
        assert_eq!(int_port.as_int(), Some(8080));

        let string_port = TargetPort::String("http".to_string());
        assert_eq!(string_port.as_int(), None);
    }
}
