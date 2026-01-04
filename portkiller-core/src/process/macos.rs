//! macOS-specific process management implementation
//!
//! Uses the following system commands:
//! - `/bin/kill -15 PID` for SIGTERM (graceful)
//! - `/bin/kill -9 PID` for SIGKILL (force)
//! - `ps -p PID` to check if process is running

use super::{KillError, ProcessManager};
use tokio::process::Command;
use tokio::time::{sleep, Duration};
use tracing::{debug, warn};

/// Grace period to wait between SIGTERM and SIGKILL (500ms)
const GRACEFUL_KILL_TIMEOUT_MS: u64 = 500;

/// macOS process manager implementation
///
/// This implementation uses the standard Unix signals:
/// - SIGTERM (15): Graceful termination request
/// - SIGKILL (9): Immediate forced termination
#[derive(Debug, Default)]
pub struct MacOsProcessManager;

impl MacOsProcessManager {
    /// Create a new MacOsProcessManager instance
    pub fn new() -> Self {
        Self
    }

    /// Send a signal to a process using /bin/kill
    ///
    /// # Arguments
    ///
    /// * `pid` - The process ID
    /// * `signal` - The signal to send (e.g., "15" for SIGTERM, "9" for SIGKILL)
    ///
    /// # Returns
    ///
    /// * `Ok(true)` - Signal sent successfully
    /// * `Ok(false)` - Process not found or already terminated
    /// * `Err(KillError)` - Error sending signal
    async fn send_signal(&self, pid: u32, signal: &str) -> Result<bool, KillError> {
        debug!(pid = pid, signal = signal, "Sending signal to process");

        let output = Command::new("/bin/kill")
            .arg(format!("-{}", signal))
            .arg(pid.to_string())
            .output()
            .await?;

        if output.status.success() {
            debug!(pid = pid, signal = signal, "Signal sent successfully");
            return Ok(true);
        }

        // Check stderr for common error conditions
        let stderr = String::from_utf8_lossy(&output.stderr);

        if stderr.contains("No such process") {
            debug!(pid = pid, "Process not found");
            return Err(KillError::ProcessNotFound(pid));
        }

        if stderr.contains("Operation not permitted") || stderr.contains("Permission denied") {
            warn!(pid = pid, "Permission denied to kill process");
            return Err(KillError::PermissionDenied(pid));
        }

        // Exit code 1 often means the process doesn't exist
        if output.status.code() == Some(1) {
            debug!(pid = pid, "Process may not exist (exit code 1)");
            return Ok(false);
        }

        Err(KillError::CommandFailed(format!(
            "kill -{} {} failed: {}",
            signal,
            pid,
            stderr.trim()
        )))
    }
}

impl ProcessManager for MacOsProcessManager {
    /// Kill a process gracefully with fallback to force kill
    ///
    /// Strategy:
    /// 1. Send SIGTERM (signal 15) for graceful shutdown
    /// 2. Wait 500ms for process to clean up
    /// 3. Check if process is still running
    /// 4. If still running, send SIGKILL (signal 9)
    async fn kill_gracefully(&self, pid: u32) -> Result<bool, KillError> {
        debug!(pid = pid, "Attempting graceful kill");

        // Step 1: Send SIGTERM
        match self.send_signal(pid, "15").await {
            Ok(true) => {
                debug!(pid = pid, "SIGTERM sent, waiting for process to terminate");
            }
            Ok(false) => {
                // Process might already be gone
                debug!(pid = pid, "SIGTERM returned false, process may be gone");
            }
            Err(KillError::ProcessNotFound(_)) => {
                // Process already gone
                debug!(pid = pid, "Process not found, already terminated");
                return Ok(true);
            }
            Err(e) => {
                warn!(pid = pid, error = %e, "Failed to send SIGTERM");
                return Err(e);
            }
        }

        // Step 2: Wait for grace period
        sleep(Duration::from_millis(GRACEFUL_KILL_TIMEOUT_MS)).await;

        // Step 3: Check if process is still running
        if !self.is_process_running(pid).await {
            debug!(pid = pid, "Process terminated after SIGTERM");
            return Ok(true);
        }

        // Step 4: Force kill with SIGKILL
        debug!(pid = pid, "Process still running, sending SIGKILL");
        self.kill_force(pid).await
    }

    /// Force kill a process with SIGKILL (signal 9)
    async fn kill_force(&self, pid: u32) -> Result<bool, KillError> {
        debug!(pid = pid, "Force killing process with SIGKILL");

        match self.send_signal(pid, "9").await {
            Ok(true) => {
                debug!(pid = pid, "SIGKILL sent successfully");
                Ok(true)
            }
            Ok(false) => {
                // Process might already be gone
                debug!(pid = pid, "SIGKILL returned false");
                Ok(false)
            }
            Err(KillError::ProcessNotFound(_)) => {
                // Process already gone - consider this a success
                debug!(pid = pid, "Process not found during force kill");
                Ok(true)
            }
            Err(e) => Err(e),
        }
    }

    /// Check if a process is currently running using `ps -p PID`
    async fn is_process_running(&self, pid: u32) -> bool {
        let result = Command::new("/bin/ps")
            .arg("-p")
            .arg(pid.to_string())
            .output()
            .await;

        match result {
            Ok(output) => {
                // ps -p returns exit code 0 if process exists, 1 if not
                let running = output.status.success();
                debug!(pid = pid, running = running, "Process running check");
                running
            }
            Err(e) => {
                warn!(pid = pid, error = %e, "Failed to check if process is running");
                false
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_is_process_running_current_process() {
        let manager = MacOsProcessManager::new();
        let current_pid = std::process::id();

        // Current process should be running
        assert!(manager.is_process_running(current_pid).await);
    }

    #[tokio::test]
    async fn test_is_process_running_nonexistent() {
        let manager = MacOsProcessManager::new();

        // PID 0 is kernel, try a very high PID that likely doesn't exist
        // Note: This test might be flaky on systems with many processes
        let fake_pid = 999999999;
        assert!(!manager.is_process_running(fake_pid).await);
    }

    #[tokio::test]
    async fn test_kill_nonexistent_process() {
        let manager = MacOsProcessManager::new();
        let fake_pid = 999999999;

        let result = manager.kill_force(fake_pid).await;
        // Should either succeed (process already gone) or return ProcessNotFound
        match result {
            Ok(_) => {} // Success is acceptable
            Err(KillError::ProcessNotFound(_)) => {} // Also acceptable
            Err(e) => panic!("Unexpected error: {}", e),
        }
    }
}
