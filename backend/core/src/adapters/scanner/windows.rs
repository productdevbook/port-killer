//! Windows port scanner implementation using netstat.

use crate::domain::PortInfo;
use crate::error::{Error, Result};

use super::Scanner;

/// Windows-specific port scanner.
pub struct WindowsScanner;

impl WindowsScanner {
    pub fn new() -> Self {
        Self
    }
}

impl Default for WindowsScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl Scanner for WindowsScanner {
    async fn scan(&self) -> Result<Vec<PortInfo>> {
        // TODO: Implement Windows-specific scanning using netstat
        Err(Error::UnsupportedPlatform(
            "Windows scanner not yet implemented".to_string(),
        ))
    }
}
