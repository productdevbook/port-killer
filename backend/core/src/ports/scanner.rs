//! Port scanner port (interface).

use crate::domain::PortInfo;
use crate::error::Result;

/// Port for scanning network ports.
///
/// This trait defines the interface for port scanning functionality.
/// Implementations handle platform-specific details (lsof, netstat, etc.)
pub trait PortScannerPort: Send + Sync {
    /// Scan for all listening TCP ports.
    ///
    /// Returns a list of active ports with their associated process information.
    fn scan(&self) -> impl std::future::Future<Output = Result<Vec<PortInfo>>> + Send;
}
