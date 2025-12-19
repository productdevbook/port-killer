//! UniFFI bindings for portkiller-core library.
//!
//! This crate provides FFI bindings that can be used from Swift via XCFramework.
//! Types are prefixed with "Rust" to avoid conflicts with Swift's native types.

use tokio::runtime::Runtime;

use portkiller_core::{
    PortInfo as CorePortInfo, PortScanner as CoreScanner, ProcessKiller as CoreKiller,
    ProcessType as CoreProcessType,
};

uniffi::include_scaffolding!("lib");

/// Error type exposed via FFI.
/// Named RustScannerError to avoid conflict with Swift's PortKillerError.
#[derive(Debug, thiserror::Error)]
pub enum RustScannerError {
    #[error("Scan failed: {msg}")]
    ScanFailed { msg: String },

    #[error("Kill failed: {msg}")]
    KillFailed { msg: String },

    #[error("Permission denied: {msg}")]
    PermissionDenied { msg: String },
}

/// Port information exposed to Swift.
/// Named RustPortInfo to avoid conflict with Swift's PortInfo.
#[derive(Debug, Clone)]
pub struct RustPortInfo {
    pub id: String,
    pub port: u16,
    pub pid: u32,
    pub process_name: String,
    pub address: String,
    pub user: String,
    pub command: String,
    pub fd: String,
    pub is_active: bool,
    pub process_type: String,
}

impl From<CorePortInfo> for RustPortInfo {
    fn from(p: CorePortInfo) -> Self {
        Self {
            id: p.id.to_string(),
            port: p.port,
            pid: p.pid,
            process_name: p.process_name.clone(),
            address: p.address.clone(),
            user: p.user.clone(),
            command: p.command.clone(),
            fd: p.fd.clone(),
            is_active: p.is_active,
            process_type: process_type_to_string(CoreProcessType::detect(&p.process_name)),
        }
    }
}

fn process_type_to_string(pt: CoreProcessType) -> String {
    match pt {
        CoreProcessType::WebServer => "webServer".to_string(),
        CoreProcessType::Database => "database".to_string(),
        CoreProcessType::Development => "development".to_string(),
        CoreProcessType::System => "system".to_string(),
        CoreProcessType::Other => "other".to_string(),
    }
}

/// Main scanner interface exposed via FFI.
/// Named RustScanner to avoid conflict with Swift's PortScanner.
pub struct RustScanner {
    runtime: Runtime,
    scanner: CoreScanner,
    killer: CoreKiller,
}

impl RustScanner {
    /// Create a new scanner instance.
    pub fn new() -> Self {
        let runtime = Runtime::new().expect("Failed to create Tokio runtime");
        Self {
            runtime,
            scanner: CoreScanner::new(),
            killer: CoreKiller::new(),
        }
    }

    /// Scan all listening TCP ports.
    pub fn scan_ports(&self) -> Result<Vec<RustPortInfo>, RustScannerError> {
        self.runtime.block_on(async {
            self.scanner
                .scan()
                .await
                .map(|ports| ports.into_iter().map(Into::into).collect())
                .map_err(|e| RustScannerError::ScanFailed { msg: e.to_string() })
        })
    }

    /// Kill a process gracefully (SIGTERM, wait, then SIGKILL).
    pub fn kill_process(&self, pid: u32) -> Result<bool, RustScannerError> {
        self.runtime.block_on(async {
            self.killer.kill_gracefully(pid).await.map_err(|e| {
                if e.to_string().contains("Permission denied") {
                    RustScannerError::PermissionDenied { msg: e.to_string() }
                } else {
                    RustScannerError::KillFailed { msg: e.to_string() }
                }
            })
        })
    }

    /// Force kill a process immediately (SIGKILL).
    pub fn force_kill_process(&self, pid: u32) -> Result<bool, RustScannerError> {
        self.runtime.block_on(async {
            self.killer.kill(pid, true).await.map_err(|e| {
                if e.to_string().contains("Permission denied") {
                    RustScannerError::PermissionDenied { msg: e.to_string() }
                } else {
                    RustScannerError::KillFailed { msg: e.to_string() }
                }
            })
        })
    }

    /// Check if a process is currently running.
    pub fn is_process_running(&self, pid: u32) -> bool {
        self.killer.is_running(pid)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scanner_creation() {
        let scanner = RustScanner::new();
        // Should not panic
        assert!(!scanner.is_process_running(999999999));
    }

    #[test]
    fn test_scan_ports() {
        let scanner = RustScanner::new();
        let result = scanner.scan_ports();
        // Scan should succeed (may return empty list if no ports listening)
        assert!(result.is_ok());
    }

    #[test]
    fn test_kill_nonexistent_process() {
        let scanner = RustScanner::new();
        let result = scanner.force_kill_process(999999999);
        // Should succeed but return false (process doesn't exist)
        assert!(result.is_ok());
        assert!(!result.unwrap());
    }
}
