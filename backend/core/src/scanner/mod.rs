//! Port scanning functionality with platform-specific implementations.

#[cfg(target_os = "macos")]
mod darwin;

#[cfg(target_os = "linux")]
mod linux;

#[cfg(target_os = "windows")]
mod windows;
mod utils;

use crate::error::Result;
use crate::models::PortInfo;

/// Trait for platform-specific port scanning implementations.
pub trait Scanner: Send + Sync {
    /// Scan all listening TCP ports.
    fn scan(&self) -> impl std::future::Future<Output = Result<Vec<PortInfo>>> + Send;
}

/// The main port scanner that uses platform-specific implementations.
pub struct PortScanner {
    #[cfg(target_os = "macos")]
    inner: darwin::DarwinScanner,

    #[cfg(target_os = "linux")]
    inner: linux::LinuxScanner,

    #[cfg(target_os = "windows")]
    inner: windows::WindowsScanner,
}

impl PortScanner {
    /// Create a new port scanner for the current platform.
    pub fn new() -> Self {
        Self {
            #[cfg(target_os = "macos")]
            inner: darwin::DarwinScanner::new(),

            #[cfg(target_os = "linux")]
            inner: linux::LinuxScanner::new(),

            #[cfg(target_os = "windows")]
            inner: windows::WindowsScanner::new(),
        }
    }

    /// Scan all listening TCP ports.
    pub async fn scan(&self) -> Result<Vec<PortInfo>> {
        self.inner.scan().await
    }
}

impl Default for PortScanner {
    fn default() -> Self {
        Self::new()
    }
}

