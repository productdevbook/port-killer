//! Process manager for kubectl port-forward and socat processes.

use parking_lot::RwLock;
use std::collections::HashMap;
use std::io::{BufRead, BufReader};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use uuid::Uuid;

use super::discovery::KubernetesDiscovery;
use super::errors::{KubectlError, Result};
use super::models::{PortForwardConnectionConfig, PortForwardProcessType};

/// Grace period before force-killing a process.
const KILL_GRACE_PERIOD: Duration = Duration::from_millis(300);

/// Time window for considering an error "recent".
const RECENT_ERROR_WINDOW: Duration = Duration::from_secs(10);

/// Manages kubectl port-forward and socat processes.
pub struct PortForwardProcessManager {
    /// Discovery service for finding kubectl/socat paths.
    discovery: KubernetesDiscovery,

    /// Running processes: connection_id -> process_type -> child process.
    processes: RwLock<HashMap<Uuid, HashMap<PortForwardProcessType, Child>>>,

    /// Recent connection errors: connection_id -> error timestamp.
    connection_errors: RwLock<HashMap<Uuid, Instant>>,
}

impl PortForwardProcessManager {
    /// Creates a new process manager.
    pub fn new() -> Self {
        Self {
            discovery: KubernetesDiscovery::new(),
            processes: RwLock::new(HashMap::new()),
            connection_errors: RwLock::new(HashMap::new()),
        }
    }

    /// Creates a new process manager with a custom discovery service.
    pub fn with_discovery(discovery: KubernetesDiscovery) -> Self {
        Self {
            discovery,
            processes: RwLock::new(HashMap::new()),
            connection_errors: RwLock::new(HashMap::new()),
        }
    }

    /// Returns the kubectl path if available.
    pub fn kubectl_path(&self) -> Option<&PathBuf> {
        self.discovery.kubectl_path()
    }

    /// Returns the socat path if available.
    pub fn socat_path(&self) -> Option<&PathBuf> {
        self.discovery.socat_path()
    }

    // =========================================================================
    // Process Lifecycle
    // =========================================================================

    /// Starts a kubectl port-forward process.
    pub fn start_port_forward(&self, id: Uuid, config: &PortForwardConnectionConfig) -> Result<()> {
        let kubectl_path = self
            .discovery
            .kubectl_path()
            .ok_or(KubectlError::KubectlNotFound)?;

        let child = Command::new(kubectl_path)
            .args([
                "port-forward",
                "-n",
                &config.namespace,
                &format!("svc/{}", config.service),
                &format!("{}:{}", config.local_port, config.remote_port),
                "--address=127.0.0.1",
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| KubectlError::ProcessError(format!("Failed to start kubectl: {}", e)))?;

        self.register_process(id, PortForwardProcessType::PortForward, child);
        Ok(())
    }

    /// Starts a standard socat proxy process.
    pub fn start_proxy(&self, id: Uuid, external_port: u16, internal_port: u16) -> Result<()> {
        let socat_path = self
            .discovery
            .socat_path()
            .ok_or(KubectlError::SocatNotFound)?;

        let child = Command::new(socat_path)
            .args([
                &format!("TCP-LISTEN:{},fork,reuseaddr", external_port),
                &format!("TCP:127.0.0.1:{}", internal_port),
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| KubectlError::ProcessError(format!("Failed to start socat: {}", e)))?;

        self.register_process(id, PortForwardProcessType::Proxy, child);
        Ok(())
    }

    /// Starts a direct exec proxy for multi-connection support.
    ///
    /// This creates a wrapper script that spawns kubectl port-forward per connection.
    pub fn start_direct_exec_proxy(
        &self,
        id: Uuid,
        config: &PortForwardConnectionConfig,
    ) -> Result<()> {
        let kubectl_path = self
            .discovery
            .kubectl_path()
            .ok_or(KubectlError::KubectlNotFound)?;

        let socat_path = self
            .discovery
            .socat_path()
            .ok_or(KubectlError::SocatNotFound)?;

        // Create wrapper script
        let script_content = create_wrapper_script(
            kubectl_path,
            socat_path,
            &config.namespace,
            &config.service,
            config.remote_port,
        );

        let script_path = std::env::temp_dir().join(format!("pf-wrapper-{}.sh", id));
        let script_path_str = script_path.to_string_lossy();

        // Write script
        std::fs::write(&script_path, script_content).map_err(|e| {
            KubectlError::ProcessError(format!("Failed to write wrapper script: {}", e))
        })?;

        // Make executable
        Command::new("chmod")
            .args(["+x", script_path_str.as_ref()])
            .status()
            .map_err(|e| KubectlError::ProcessError(format!("Failed to chmod script: {}", e)))?;

        // Start socat with EXEC
        let external_port = config.proxy_port.unwrap_or(config.local_port);
        let child = Command::new(socat_path)
            .args([
                &format!("TCP-LISTEN:{},fork,reuseaddr", external_port),
                &format!("EXEC:{}", script_path_str),
            ])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| {
                KubectlError::ProcessError(format!("Failed to start direct exec proxy: {}", e))
            })?;

        self.register_process(id, PortForwardProcessType::Proxy, child);
        Ok(())
    }

    /// Kills all processes for a connection.
    pub fn kill_processes(&self, id: Uuid) -> Result<()> {
        let mut processes = self.processes.write();

        if let Some(procs) = processes.remove(&id) {
            for (_, mut child) in procs {
                let _ = child.kill();
                let _ = child.wait(); // Wait to avoid zombies
            }
        }

        // Kill any processes using the wrapper script (catches forked children)
        let script_path = std::env::temp_dir().join(format!("pf-wrapper-{}.sh", id));
        let script_path_str = script_path.to_string_lossy();
        let _ = Command::new("pkill")
            .args(["-f", script_path_str.as_ref()])
            .status();

        // Clean up wrapper script
        let _ = std::fs::remove_file(&script_path);

        // Clear any errors
        self.connection_errors.write().remove(&id);

        Ok(())
    }

    /// Kills a specific process type for a connection.
    pub fn kill_process(&self, id: Uuid, process_type: PortForwardProcessType) -> Result<()> {
        let mut processes = self.processes.write();

        if let Some(procs) = processes.get_mut(&id) {
            if let Some(mut child) = procs.remove(&process_type) {
                let _ = child.kill();
            }
        }

        Ok(())
    }

    /// Kills all port forwarder processes (emergency cleanup).
    pub fn kill_all(&self) -> Result<()> {
        // Kill kubectl port-forward processes
        let _ = Command::new("pkill")
            .args(["-9", "-f", "kubectl.*port-forward"])
            .status();

        // Kill socat processes
        let _ = Command::new("pkill")
            .args(["-9", "-f", "socat.*TCP-LISTEN"])
            .status();

        // Wait a bit
        std::thread::sleep(Duration::from_millis(500));

        // Clear our tracking
        self.processes.write().clear();
        self.connection_errors.write().clear();

        // Clean up wrapper scripts
        let _ = std::fs::read_dir("/tmp").map(|entries| {
            for entry in entries.flatten() {
                let path = entry.path();
                if path
                    .file_name()
                    .and_then(|n| n.to_str())
                    .map(|n| n.starts_with("pf-wrapper-"))
                    .unwrap_or(false)
                {
                    let _ = std::fs::remove_file(path);
                }
            }
        });

        Ok(())
    }

    // =========================================================================
    // Status Checks
    // =========================================================================

    /// Checks if a specific process is running.
    pub fn is_process_running(&self, id: Uuid, process_type: PortForwardProcessType) -> bool {
        let mut processes = self.processes.write();

        if let Some(procs) = processes.get_mut(&id) {
            if let Some(child) = procs.get_mut(&process_type) {
                // Try to get exit status without blocking
                match child.try_wait() {
                    Ok(Some(_)) => {
                        // Process has exited
                        procs.remove(&process_type);
                        false
                    }
                    Ok(None) => true, // Still running
                    Err(_) => false,
                }
            } else {
                false
            }
        } else {
            false
        }
    }

    /// Checks if a port is open (something is listening).
    pub fn is_port_open(&self, port: u16) -> bool {
        TcpStream::connect_timeout(
            &format!("127.0.0.1:{}", port).parse().unwrap(),
            Duration::from_millis(500),
        )
        .is_ok()
    }

    /// Marks a connection as having an error.
    pub fn mark_connection_error(&self, id: Uuid) {
        self.connection_errors.write().insert(id, Instant::now());
    }

    /// Checks if a connection has had a recent error.
    pub fn has_recent_error(&self, id: Uuid) -> bool {
        self.connection_errors
            .read()
            .get(&id)
            .map(|t| t.elapsed() < RECENT_ERROR_WINDOW)
            .unwrap_or(false)
    }

    /// Clears the error flag for a connection.
    pub fn clear_error(&self, id: Uuid) {
        self.connection_errors.write().remove(&id);
    }

    // =========================================================================
    // Output Reading
    // =========================================================================

    /// Reads available output from a process.
    /// Returns (stdout_lines, stderr_lines, has_error).
    pub fn read_process_output(
        &self,
        id: Uuid,
        process_type: PortForwardProcessType,
    ) -> Vec<String> {
        let mut processes = self.processes.write();
        let mut lines = Vec::new();

        if let Some(procs) = processes.get_mut(&id) {
            if let Some(child) = procs.get_mut(&process_type) {
                // Read from stdout
                if let Some(ref mut stdout) = child.stdout {
                    let reader = BufReader::new(stdout);
                    for line in reader.lines().take(100).flatten() {
                        lines.push(line);
                    }
                }

                // Read from stderr
                if let Some(ref mut stderr) = child.stderr {
                    let reader = BufReader::new(stderr);
                    for line in reader.lines().take(100).flatten() {
                        lines.push(line);
                    }
                }
            }
        }

        lines
    }

    // =========================================================================
    // Port Conflict Resolution
    // =========================================================================

    /// Kills any process using a specific port.
    pub fn kill_process_on_port(&self, port: u16) -> Result<()> {
        // Use lsof to find PIDs
        let output = Command::new("lsof")
            .args(["-ti", &format!("tcp:{}", port)])
            .output()
            .map_err(|e| KubectlError::ProcessError(format!("Failed to run lsof: {}", e)))?;

        if output.status.success() {
            let pids_str = String::from_utf8_lossy(&output.stdout);
            for pid_str in pids_str.lines() {
                if let Ok(pid) = pid_str.trim().parse::<i32>() {
                    // Try SIGTERM first
                    let _ = Command::new("kill")
                        .args(["-15", &pid.to_string()])
                        .status();

                    // Wait briefly
                    std::thread::sleep(KILL_GRACE_PERIOD);

                    // Check if still running and force kill
                    if Command::new("kill")
                        .args(["-0", &pid.to_string()])
                        .status()
                        .map(|s| s.success())
                        .unwrap_or(false)
                    {
                        let _ = Command::new("kill").args(["-9", &pid.to_string()]).status();
                    }
                }
            }
        }

        Ok(())
    }

    // =========================================================================
    // Internal Helpers
    // =========================================================================

    fn register_process(&self, id: Uuid, process_type: PortForwardProcessType, child: Child) {
        let mut processes = self.processes.write();
        let entry = processes.entry(id).or_default();

        // Kill existing process of the same type before registering new one
        if let Some(mut old_child) = entry.remove(&process_type) {
            let _ = old_child.kill();
            let _ = old_child.wait(); // Wait to avoid zombies
        }

        entry.insert(process_type, child);
    }
}

impl Default for PortForwardProcessManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Creates a bash wrapper script for multi-connection proxy.
fn create_wrapper_script(
    kubectl_path: &Path,
    socat_path: &Path,
    namespace: &str,
    service: &str,
    remote_port: u16,
) -> String {
    format!(
        r#"#!/bin/bash
PORT=$((30000 + ($$ % 30000)))
while /usr/bin/nc -z 127.0.0.1 $PORT 2>/dev/null; do
    PORT=$((PORT + 1))
done
{kubectl} port-forward -n {namespace} svc/{service} $PORT:{remote_port} --address=127.0.0.1 >/dev/null 2>&1 &
KPID=$!
trap "kill $KPID 2>/dev/null" EXIT
for i in 1 2 3 4 5 6 7 8 9 10; do
    if /usr/bin/nc -z 127.0.0.1 $PORT 2>/dev/null; then break; fi
    sleep 0.5
done
{socat} - TCP:127.0.0.1:$PORT
"#,
        kubectl = kubectl_path.display(),
        socat = socat_path.display(),
        namespace = namespace,
        service = service,
        remote_port = remote_port
    )
}

// ============================================================================
// Output Parsing
// ============================================================================

/// Checks if a line indicates an error.
pub fn is_error_line(line: &str) -> bool {
    let line_lower = line.to_lowercase();
    line_lower.contains("error")
        || line_lower.contains("failed")
        || line_lower.contains("unable to")
        || line_lower.contains("connection refused")
        || line_lower.contains("lost connection")
        || line_lower.contains("an error occurred")
}

/// Detects port conflict from output line.
/// Returns the conflicting port if detected.
pub fn detect_port_conflict(line: &str) -> Option<u16> {
    // kubectl format: "listen tcp4 127.0.0.1:8080: bind: address already in use"
    // socat format: "socat[12345] E bind(5, {AF=2 0.0.0.0:9090}, 16): Address already in use"

    if !line.to_lowercase().contains("address already in use") {
        return None;
    }

    // Try to extract port number after IP address patterns (x.x.x.x:PORT or [::]:PORT)
    // Look for patterns like ":8080" followed by non-digit
    for (i, part) in line.split(':').enumerate() {
        // Skip first part (before any colon) and parts that are just IP octets
        if i == 0 {
            continue;
        }

        // Extract leading digits from this part
        let digits: String = part.chars().take_while(|c| c.is_ascii_digit()).collect();
        if digits.is_empty() {
            continue;
        }

        if let Ok(port) = digits.parse::<u16>() {
            // Reasonable port range (skip IP octets which are typically small numbers like 0-255)
            if port > 255 {
                return Some(port);
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_error_line() {
        assert!(is_error_line("Error: connection refused"));
        assert!(is_error_line("Failed to connect"));
        assert!(is_error_line("Unable to establish connection"));
        assert!(is_error_line("Lost connection to server"));
        assert!(!is_error_line("Forwarding from 127.0.0.1:8080"));
    }

    #[test]
    fn test_detect_port_conflict() {
        let kubectl_error = "listen tcp4 127.0.0.1:8080: bind: address already in use";
        assert_eq!(detect_port_conflict(kubectl_error), Some(8080));

        let socat_error = "socat[12345] E bind(5, {AF=2 0.0.0.0:9090}, 16): Address already in use";
        assert_eq!(detect_port_conflict(socat_error), Some(9090));

        let no_conflict = "Forwarding from 127.0.0.1:8080 -> 80";
        assert_eq!(detect_port_conflict(no_conflict), None);
    }

    #[test]
    fn test_create_wrapper_script() {
        let script = create_wrapper_script(
            &PathBuf::from("/usr/bin/kubectl"),
            &PathBuf::from("/usr/bin/socat"),
            "default",
            "my-service",
            80,
        );

        assert!(script.contains("#!/bin/bash"));
        assert!(script.contains("/usr/bin/kubectl port-forward"));
        assert!(script.contains("-n default"));
        assert!(script.contains("svc/my-service"));
        assert!(script.contains(":80"));
    }
}
