//! Windows-specific process management implementation
//!
//! Uses the following system commands:
//! - `taskkill /PID xxx` for graceful termination
//! - `taskkill /PID xxx /F` for forced termination
//! - `tasklist /FI "PID eq xxx"` to check if process is running

use super::{KillError, ProcessManager};
use tokio::process::Command;
use tokio::time::{sleep, Duration};
use tracing::{debug, warn};

/// Grace period to wait between normal and forced taskkill (500ms)
const GRACEFUL_KILL_TIMEOUT_MS: u64 = 500;

/// Windows process manager implementation
///
/// This implementation uses the Windows taskkill utility:
/// - `taskkill /PID xxx`: Request graceful termination (sends WM_CLOSE)
/// - `taskkill /PID xxx /F`: Force termination (TerminateProcess)
#[derive(Debug, Default)]
pub struct WindowsProcessManager;

impl WindowsProcessManager {
    /// Create a new WindowsProcessManager instance
    pub fn new() -> Self {
        Self
    }

    /// Terminate a process using taskkill
    ///
    /// # Arguments
    ///
    /// * `pid` - The process ID
    /// * `force` - Whether to use /F flag for forced termination
    ///
    /// # Returns
    ///
    /// * `Ok(true)` - Process terminated successfully
    /// * `Ok(false)` - Process not found or already terminated
    /// * `Err(KillError)` - Error terminating process
    async fn taskkill(&self, pid: u32, force: bool) -> Result<bool, KillError> {
        debug!(pid = pid, force = force, "Executing taskkill");

        let mut cmd = Command::new("taskkill");
        cmd.arg("/PID").arg(pid.to_string());

        if force {
            cmd.arg("/F");
        }

        let output = cmd.output().await?;

        if output.status.success() {
            debug!(pid = pid, force = force, "taskkill succeeded");
            return Ok(true);
        }

        // Check stderr and stdout for common error conditions
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        let combined = format!("{} {}", stdout, stderr);

        // Common error messages from taskkill
        if combined.contains("not found") || combined.contains("could not be found") {
            debug!(pid = pid, "Process not found");
            return Err(KillError::ProcessNotFound(pid));
        }

        if combined.contains("Access is denied") || combined.contains("access denied") {
            warn!(pid = pid, "Access denied to kill process");
            return Err(KillError::PermissionDenied(pid));
        }

        // "The process has already been terminated" is also a success
        if combined.contains("already been terminated") || combined.contains("has exited") {
            debug!(pid = pid, "Process already terminated");
            return Ok(true);
        }

        Err(KillError::CommandFailed(format!(
            "taskkill /PID {} {} failed: {}",
            pid,
            if force { "/F" } else { "" },
            combined.trim()
        )))
    }
}

impl ProcessManager for WindowsProcessManager {
    /// Kill a process gracefully with fallback to force kill
    ///
    /// Strategy:
    /// 1. Use `taskkill /PID xxx` for graceful shutdown (sends WM_CLOSE)
    /// 2. Wait 500ms for process to clean up
    /// 3. Check if process is still running
    /// 4. If still running, use `taskkill /PID xxx /F` for force termination
    async fn kill_gracefully(&self, pid: u32) -> Result<bool, KillError> {
        debug!(pid = pid, "Attempting graceful kill");

        // Step 1: Send graceful taskkill (without /F)
        match self.taskkill(pid, false).await {
            Ok(true) => {
                debug!(pid = pid, "Graceful taskkill sent, waiting for process to terminate");
            }
            Ok(false) => {
                debug!(pid = pid, "Graceful taskkill returned false, process may be gone");
            }
            Err(KillError::ProcessNotFound(_)) => {
                debug!(pid = pid, "Process not found, already terminated");
                return Ok(true);
            }
            Err(e) => {
                // On Windows, graceful taskkill may fail for console apps
                // Continue to force kill in this case
                warn!(pid = pid, error = %e, "Graceful taskkill failed, will try force");
            }
        }

        // Step 2: Wait for grace period
        sleep(Duration::from_millis(GRACEFUL_KILL_TIMEOUT_MS)).await;

        // Step 3: Check if process is still running
        if !self.is_process_running(pid).await {
            debug!(pid = pid, "Process terminated after graceful taskkill");
            return Ok(true);
        }

        // Step 4: Force kill with /F flag
        debug!(pid = pid, "Process still running, sending taskkill /F");
        self.kill_force(pid).await
    }

    /// Force kill a process with `taskkill /F`
    async fn kill_force(&self, pid: u32) -> Result<bool, KillError> {
        debug!(pid = pid, "Force killing process with taskkill /F");

        match self.taskkill(pid, true).await {
            Ok(true) => {
                debug!(pid = pid, "taskkill /F succeeded");
                Ok(true)
            }
            Ok(false) => {
                debug!(pid = pid, "taskkill /F returned false");
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

    /// Check if a process is currently running using `tasklist`
    ///
    /// Uses: `tasklist /FI "PID eq xxx" /NH`
    /// - /FI: Filter by PID
    /// - /NH: No header (cleaner output)
    async fn is_process_running(&self, pid: u32) -> bool {
        let result = Command::new("tasklist")
            .args(["/FI", &format!("PID eq {}", pid), "/NH"])
            .output()
            .await;

        match result {
            Ok(output) => {
                let stdout = String::from_utf8_lossy(&output.stdout);

                // tasklist returns "INFO: No tasks are running..." if not found
                // Otherwise it returns the process info line
                let running = output.status.success()
                    && !stdout.contains("No tasks are running")
                    && !stdout.contains("INFO:")
                    && stdout.contains(&pid.to_string());

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
        let manager = WindowsProcessManager::new();
        let current_pid = std::process::id();

        // Current process should be running
        assert!(manager.is_process_running(current_pid).await);
    }

    #[tokio::test]
    async fn test_is_process_running_nonexistent() {
        let manager = WindowsProcessManager::new();

        // Try a very high PID that likely doesn't exist
        let fake_pid = 999999999;
        assert!(!manager.is_process_running(fake_pid).await);
    }

    #[tokio::test]
    async fn test_kill_nonexistent_process() {
        let manager = WindowsProcessManager::new();
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
