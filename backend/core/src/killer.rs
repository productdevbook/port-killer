//! Process killing functionality with graceful shutdown support.

use std::time::Duration;

use tokio::time::sleep;

use crate::error::{Error, Result};

/// Process killer with support for graceful and forceful termination.
///
/// Provides methods to kill processes using SIGTERM (graceful) or SIGKILL (force).
/// The graceful kill strategy sends SIGTERM first, waits for the process to
/// clean up, then sends SIGKILL if necessary.
pub struct ProcessKiller {
    /// Grace period between SIGTERM and SIGKILL (default: 500ms).
    grace_period: Duration,
}

impl ProcessKiller {
    /// Create a new process killer with default settings.
    pub fn new() -> Self {
        Self {
            grace_period: Duration::from_millis(500),
        }
    }

    /// Create a process killer with a custom grace period.
    pub fn with_grace_period(grace_period: Duration) -> Self {
        Self { grace_period }
    }

    /// Kill a process by sending a termination signal.
    ///
    /// # Arguments
    /// * `pid` - The process ID to kill
    /// * `force` - If true, sends SIGKILL; otherwise sends SIGTERM
    ///
    /// # Returns
    /// * `Ok(true)` if the kill signal was sent successfully
    /// * `Ok(false)` if the process doesn't exist or already terminated
    /// * `Err` if there was an error sending the signal
    #[cfg(unix)]
    pub async fn kill(&self, pid: u32, force: bool) -> Result<bool> {
        use nix::sys::signal::{kill, Signal};
        use nix::unistd::Pid;

        let signal = if force {
            Signal::SIGKILL
        } else {
            Signal::SIGTERM
        };

        let nix_pid = Pid::from_raw(pid as i32);

        match kill(nix_pid, signal) {
            Ok(()) => Ok(true),
            Err(nix::errno::Errno::ESRCH) => {
                // Process doesn't exist - consider this success
                Ok(false)
            }
            Err(nix::errno::Errno::EPERM) => Err(Error::PermissionDenied(format!(
                "Permission denied to kill process {}",
                pid
            ))),
            Err(e) => Err(Error::KillFailed {
                pid,
                reason: e.to_string(),
            }),
        }
    }

    /// Kill a process on Windows.
    #[cfg(windows)]
    pub async fn kill(&self, pid: u32, _force: bool) -> Result<bool> {
        use std::process::Command;

        let output = Command::new("taskkill")
            .args(["/F", "/PID", &pid.to_string()])
            .output()
            .map_err(|e| Error::CommandFailed(format!("Failed to run taskkill: {}", e)))?;

        if output.status.success() {
            Ok(true)
        } else {
            let stderr = String::from_utf8_lossy(&output.stderr);
            if stderr.contains("not found") || stderr.contains("No such process") {
                Ok(false)
            } else {
                Err(Error::KillFailed {
                    pid,
                    reason: stderr.to_string(),
                })
            }
        }
    }

    /// Attempt to kill a process gracefully, falling back to force kill if needed.
    ///
    /// Strategy:
    /// 1. Send SIGTERM (graceful shutdown signal)
    /// 2. Wait for the grace period
    /// 3. Send SIGKILL (immediate termination)
    ///
    /// This two-stage approach allows processes to:
    /// - Close file handles properly
    /// - Flush buffers to disk
    /// - Send shutdown notifications
    /// - Clean up temporary resources
    ///
    /// # Arguments
    /// * `pid` - The process ID to kill
    ///
    /// # Returns
    /// * `Ok(true)` if the process was killed
    /// * `Ok(false)` if the process didn't exist
    /// * `Err` if there was an error
    pub async fn kill_gracefully(&self, pid: u32) -> Result<bool> {
        // Try SIGTERM first
        let graceful_result = self.kill(pid, false).await?;

        if graceful_result {
            // Give the process time to clean up
            sleep(self.grace_period).await;
        }

        // Force kill with SIGKILL
        self.kill(pid, true).await
    }

    /// Check if a process is running.
    #[cfg(unix)]
    pub fn is_running(&self, pid: u32) -> bool {
        use nix::sys::signal::kill;
        use nix::unistd::Pid;

        // Sending signal 0 checks if the process exists without actually sending a signal
        kill(Pid::from_raw(pid as i32), None).is_ok()
    }

    /// Check if a process is running on Windows.
    #[cfg(windows)]
    pub fn is_running(&self, pid: u32) -> bool {
        use std::process::Command;

        Command::new("tasklist")
            .args(["/FI", &format!("PID eq {}", pid)])
            .output()
            .map(|o| {
                let stdout = String::from_utf8_lossy(&o.stdout);
                stdout.contains(&pid.to_string())
            })
            .unwrap_or(false)
    }
}

impl Default for ProcessKiller {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_grace_period() {
        let killer = ProcessKiller::new();
        assert_eq!(killer.grace_period, Duration::from_millis(500));
    }

    #[test]
    fn test_custom_grace_period() {
        let killer = ProcessKiller::with_grace_period(Duration::from_secs(2));
        assert_eq!(killer.grace_period, Duration::from_secs(2));
    }

    #[tokio::test]
    async fn test_kill_nonexistent_process() {
        let killer = ProcessKiller::new();
        // Use a very high PID that shouldn't exist
        let result = killer.kill(999999999, false).await;
        assert!(result.is_ok());
        assert!(!result.unwrap()); // Process doesn't exist
    }

    #[test]
    fn test_is_running_nonexistent() {
        let killer = ProcessKiller::new();
        assert!(!killer.is_running(999999999));
    }
}
