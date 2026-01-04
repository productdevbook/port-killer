//! PortKiller Core - Cross-platform port scanning and process management
//!
//! This library provides platform-agnostic APIs for:
//! - Scanning TCP listening ports
//! - Killing processes by PID
//! - Managing Kubernetes port forwards
//! - Managing Cloudflare tunnels

pub mod models;
pub mod process;
pub mod scanner;

// Re-export main types
pub use models::{PortInfo, ProcessType};
pub use process::{kill_process, kill_process_gracefully, ProcessManager};
pub use scanner::{scan_ports, PortScanner};

/// Library version
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Main entry point for the PortKiller core functionality
pub struct PortKillerCore {
    scanner: scanner::PlatformScanner,
    process_manager: process::PlatformProcessManager,
}

impl PortKillerCore {
    /// Create a new PortKillerCore instance
    pub fn new() -> Self {
        Self {
            scanner: scanner::PlatformScanner::new(),
            process_manager: process::PlatformProcessManager::new(),
        }
    }

    /// Scan for all listening TCP ports
    pub async fn scan_ports(&self) -> Result<Vec<PortInfo>, scanner::ScanError> {
        self.scanner.scan_ports().await
    }

    /// Kill a process by PID with graceful shutdown (SIGTERM then SIGKILL)
    pub async fn kill_process_gracefully(&self, pid: u32) -> Result<bool, process::KillError> {
        self.process_manager.kill_gracefully(pid).await
    }

    /// Kill a process by PID immediately (force kill)
    pub async fn kill_process_force(&self, pid: u32) -> Result<bool, process::KillError> {
        self.process_manager.kill_force(pid).await
    }

    /// Get PIDs of processes using a specific port
    pub async fn get_pids_on_port(&self, port: u16) -> Result<Vec<u32>, scanner::ScanError> {
        self.scanner.get_pids_on_port(port).await
    }
}

impl Default for PortKillerCore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_scan_ports() {
        let core = PortKillerCore::new();
        let result = core.scan_ports().await;
        assert!(result.is_ok());
    }
}
