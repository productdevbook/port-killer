//! Port scanning application service.

use std::collections::HashSet;

use parking_lot::RwLock;

use crate::domain::{filter_ports, PortFilter, PortInfo, WatchedPort};
use crate::error::Result;
use crate::ports::PortScannerPort;

/// Application service for port scanning operations.
///
/// This service handles port scanning, caching, and filtering.
/// It uses the `PortScannerPort` trait for the actual scanning,
/// allowing different implementations to be injected.
pub struct PortService<S: PortScannerPort> {
    scanner: S,
    ports_cache: RwLock<Vec<PortInfo>>,
}

impl<S: PortScannerPort> PortService<S> {
    /// Create a new port service with the given scanner.
    pub fn new(scanner: S) -> Self {
        Self {
            scanner,
            ports_cache: RwLock::new(Vec::new()),
        }
    }

    /// Refresh the port cache by scanning.
    pub async fn refresh(&self) -> Result<()> {
        let ports = self.scanner.scan().await?;
        *self.ports_cache.write() = ports;
        Ok(())
    }

    /// Get all cached ports.
    pub fn get_ports(&self) -> Vec<PortInfo> {
        self.ports_cache.read().clone()
    }

    /// Get ports filtered by the given criteria.
    pub fn get_filtered_ports(
        &self,
        filter: &PortFilter,
        favorites: &HashSet<u16>,
        watched: &[WatchedPort],
    ) -> Vec<PortInfo> {
        let ports = self.ports_cache.read();
        filter_ports(&ports, filter, favorites, watched)
    }

    /// Find a port by port number.
    pub fn find_by_port(&self, port: u16) -> Option<PortInfo> {
        self.ports_cache
            .read()
            .iter()
            .find(|p| p.port == port)
            .cloned()
    }

    /// Find ports by PID.
    pub fn find_by_pid(&self, pid: u32) -> Vec<PortInfo> {
        self.ports_cache
            .read()
            .iter()
            .filter(|p| p.pid == pid)
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    /// Mock scanner for testing.
    struct MockScanner {
        ports: Arc<RwLock<Vec<PortInfo>>>,
    }

    impl MockScanner {
        fn new(ports: Vec<PortInfo>) -> Self {
            Self {
                ports: Arc::new(RwLock::new(ports)),
            }
        }
    }

    impl PortScannerPort for MockScanner {
        async fn scan(&self) -> Result<Vec<PortInfo>> {
            Ok(self.ports.read().clone())
        }
    }

    #[tokio::test]
    async fn test_port_service_refresh() {
        let mock_ports = vec![
            PortInfo::active(3000, 1234, "node", "*", "user", "node server.js", "19u"),
            PortInfo::active(8080, 5678, "nginx", "*", "root", "nginx", "6u"),
        ];

        let service = PortService::new(MockScanner::new(mock_ports));

        // Initially empty
        assert!(service.get_ports().is_empty());

        // After refresh
        service.refresh().await.unwrap();
        assert_eq!(service.get_ports().len(), 2);
    }

    #[tokio::test]
    async fn test_find_by_port() {
        let mock_ports = vec![
            PortInfo::active(3000, 1234, "node", "*", "user", "node", "19u"),
        ];

        let service = PortService::new(MockScanner::new(mock_ports));
        service.refresh().await.unwrap();

        let found = service.find_by_port(3000);
        assert!(found.is_some());
        assert_eq!(found.unwrap().process_name, "node");

        let not_found = service.find_by_port(9999);
        assert!(not_found.is_none());
    }
}
