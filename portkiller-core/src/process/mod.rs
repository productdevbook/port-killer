//! Process management module for killing processes by PID
//!
//! This module provides cross-platform process termination functionality
//! with support for both graceful (SIGTERM/taskkill) and forced (SIGKILL/taskkill /F) termination.
//!
//! # Graceful Kill Pattern
//!
//! The graceful kill follows this pattern:
//! 1. Send SIGTERM (or normal taskkill on Windows) to request graceful shutdown
//! 2. Wait 500ms for the process to clean up
//! 3. Check if process is still running
//! 4. If still running, send SIGKILL (or taskkill /F on Windows) for immediate termination

use thiserror::Error;

#[cfg(target_os = "macos")]
mod macos;

#[cfg(target_os = "windows")]
mod windows;

/// Errors that can occur during process killing
#[derive(Debug, Error)]
pub enum KillError {
    /// The specified process was not found
    #[error("Process with PID {0} not found")]
    ProcessNotFound(u32),

    /// Permission denied to kill the process
    #[error("Permission denied to kill process {0}")]
    PermissionDenied(u32),

    /// Failed to execute the kill command
    #[error("Failed to execute kill command: {0}")]
    CommandFailed(String),

    /// The process could not be terminated
    #[error("Failed to terminate process {0}: {1}")]
    TerminationFailed(u32, String),

    /// An I/O error occurred
    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),
}

/// Trait for platform-specific process management
///
/// This trait defines the interface for killing processes and checking
/// their running status. Implementations are provided for macOS and Windows.
#[allow(async_fn_in_trait)]
pub trait ProcessManager: Send + Sync {
    /// Kill a process gracefully with fallback to force kill
    ///
    /// This method:
    /// 1. Sends SIGTERM (macOS) or taskkill (Windows) for graceful shutdown
    /// 2. Waits 500ms for the process to terminate
    /// 3. If still running, sends SIGKILL (macOS) or taskkill /F (Windows)
    ///
    /// # Arguments
    ///
    /// * `pid` - The process ID to kill
    ///
    /// # Returns
    ///
    /// * `Ok(true)` - The process was successfully terminated
    /// * `Ok(false)` - The kill command executed but process may still be running
    /// * `Err(KillError)` - An error occurred during the kill operation
    async fn kill_gracefully(&self, pid: u32) -> Result<bool, KillError>;

    /// Force kill a process immediately (SIGKILL / taskkill /F)
    ///
    /// This method immediately terminates the process without giving it
    /// a chance to clean up. Use `kill_gracefully` when possible to allow
    /// the process to:
    /// - Close file handles properly
    /// - Flush buffers to disk
    /// - Send shutdown notifications
    /// - Clean up temporary resources
    ///
    /// # Arguments
    ///
    /// * `pid` - The process ID to kill
    ///
    /// # Returns
    ///
    /// * `Ok(true)` - The process was successfully terminated
    /// * `Ok(false)` - The kill command executed but process may still be running
    /// * `Err(KillError)` - An error occurred during the kill operation
    async fn kill_force(&self, pid: u32) -> Result<bool, KillError>;

    /// Check if a process is currently running
    ///
    /// # Arguments
    ///
    /// * `pid` - The process ID to check
    ///
    /// # Returns
    ///
    /// * `true` - The process is running
    /// * `false` - The process is not running or doesn't exist
    async fn is_process_running(&self, pid: u32) -> bool;
}

// Platform-specific exports
#[cfg(target_os = "macos")]
pub use macos::MacOsProcessManager as PlatformProcessManager;

#[cfg(target_os = "windows")]
pub use windows::WindowsProcessManager as PlatformProcessManager;

// Fallback for unsupported platforms (compile-time check)
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
compile_error!("Unsupported platform: only macOS and Windows are supported");

/// Kill a process by PID with graceful shutdown, falling back to force kill
///
/// This is a convenience function that creates a default process manager
/// and calls `kill_gracefully`.
///
/// # Arguments
///
/// * `pid` - The process ID to kill
///
/// # Returns
///
/// * `Ok(true)` - The process was successfully terminated
/// * `Ok(false)` - The kill command executed but process may still be running
/// * `Err(KillError)` - An error occurred during the kill operation
///
/// # Example
///
/// ```no_run
/// use portkiller_core::process::kill_process_gracefully;
///
/// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
/// let success = kill_process_gracefully(1234).await?;
/// if success {
///     println!("Process terminated successfully");
/// }
/// # Ok(())
/// # }
/// ```
pub async fn kill_process_gracefully(pid: u32) -> Result<bool, KillError> {
    let manager = PlatformProcessManager::new();
    manager.kill_gracefully(pid).await
}

/// Kill a process by PID immediately (force kill)
///
/// This is a convenience function that creates a default process manager
/// and calls `kill_force`.
///
/// # Arguments
///
/// * `pid` - The process ID to kill
///
/// # Returns
///
/// * `Ok(true)` - The process was successfully terminated
/// * `Ok(false)` - The kill command executed but process may still be running
/// * `Err(KillError)` - An error occurred during the kill operation
///
/// # Example
///
/// ```no_run
/// use portkiller_core::process::kill_process;
///
/// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
/// let success = kill_process(1234).await?;
/// if success {
///     println!("Process terminated successfully");
/// }
/// # Ok(())
/// # }
/// ```
pub async fn kill_process(pid: u32) -> Result<bool, KillError> {
    let manager = PlatformProcessManager::new();
    manager.kill_force(pid).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kill_error_display() {
        let err = KillError::ProcessNotFound(1234);
        assert!(err.to_string().contains("1234"));

        let err = KillError::PermissionDenied(5678);
        assert!(err.to_string().contains("5678"));

        let err = KillError::CommandFailed("test error".to_string());
        assert!(err.to_string().contains("test error"));
    }
}
