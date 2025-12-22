//! Process killer port (interface).

use crate::error::Result;

/// Port for killing processes.
///
/// This trait defines the interface for process termination.
/// Implementations handle platform-specific signal handling.
pub trait ProcessKillerPort: Send + Sync {
    /// Kill a process by PID.
    ///
    /// If `force` is true, sends SIGKILL immediately.
    /// Otherwise, sends SIGTERM first and waits briefly before SIGKILL.
    fn kill(&self, pid: u32, force: bool) -> impl std::future::Future<Output = Result<bool>> + Send;

    /// Kill a process gracefully (SIGTERM, then SIGKILL after timeout).
    fn kill_gracefully(
        &self,
        pid: u32,
    ) -> impl std::future::Future<Output = Result<bool>> + Send;

    /// Check if a process is still running.
    fn is_running(&self, pid: u32) -> bool;
}
