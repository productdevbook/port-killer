//! Port scanning module
//!
//! This module provides platform-specific implementations for scanning
//! TCP listening ports on the system.

use crate::models::PortInfo;
use thiserror::Error;

// Platform-specific implementations
#[cfg(target_os = "macos")]
mod macos;

#[cfg(target_os = "windows")]
mod windows;

// Re-export platform-specific scanner as PlatformScanner
#[cfg(target_os = "macos")]
pub use macos::MacOsScanner as PlatformScanner;

#[cfg(target_os = "windows")]
pub use windows::WindowsScanner as PlatformScanner;

// Stub for unsupported platforms (Linux support can be added later)
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
pub struct PlatformScanner;

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
impl PlatformScanner {
    pub fn new() -> Self {
        Self
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
impl PlatformScanner {
    pub async fn get_pids_on_port(&self, _port: u16) -> Result<Vec<u32>, ScanError> {
        Err(ScanError::PlatformNotSupported)
    }
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
impl PortScanner for PlatformScanner {
    async fn scan_ports(&self) -> Result<Vec<PortInfo>, ScanError> {
        Err(ScanError::PlatformNotSupported)
    }
}

/// Errors that can occur during port scanning
#[derive(Debug, Error)]
pub enum ScanError {
    /// Failed to execute the scanning command
    #[error("Failed to execute scan command: {0}")]
    CommandError(String),

    /// Failed to parse command output
    #[error("Failed to parse output: {0}")]
    ParseError(String),

    /// Permission denied to scan ports
    #[error("Permission denied: {0}")]
    PermissionDenied(String),

    /// I/O error occurred
    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),

    /// Platform not supported
    #[error("Platform not supported")]
    PlatformNotSupported,
}

/// Trait for platform-specific port scanners
pub trait PortScanner: Send + Sync {
    /// Scan for all listening TCP ports
    ///
    /// Returns a list of PortInfo objects representing all processes
    /// that are listening on TCP ports.
    fn scan_ports(
        &self,
    ) -> impl std::future::Future<Output = Result<Vec<PortInfo>, ScanError>> + Send;
}

/// Convenience function to scan ports using the platform-specific scanner
pub async fn scan_ports() -> Result<Vec<PortInfo>, ScanError> {
    let scanner = PlatformScanner::new();
    scanner.scan_ports().await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_scan_ports() {
        let result = scan_ports().await;
        assert!(result.is_ok());
        // We can't guarantee any ports are listening, but the scan should succeed
    }
}
