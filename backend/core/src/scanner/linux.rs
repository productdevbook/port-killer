//! Linux port scanner implementation using ss or netstat.
//!
//! This module provides Linux-specific port scanning functionality.
//! It uses the `ss` command (preferred) or falls back to `netstat`.

use crate::error::{Error, Result};
use crate::models::PortInfo;
use regex::Regex;
use std::collections::{HashMap, HashSet};
use std::process::Stdio;
use tokio::process::Command;
use super::utils::Utils;
use super::Scanner;

/// Linux-specific port scanner.
pub struct LinuxScanner;

struct LinuxProcessInfo {
    user: String,
    command: String
}

impl LinuxScanner {

    /// Create a new Linux scanner.
    pub fn new() -> Self {
        Self
    }

    /// Get full command information and user for all processes using the ps command.
    ///
    /// Executes: `ps -axo pid.user.command --no-headers`
    ///
    /// Commands longer than 200 characters are truncated.
    async fn get_process_infos(&self) -> HashMap<u32, LinuxProcessInfo> {
        let output = match Command::new("/bin/ps")
            .args(["-axo", "pid,user,command", "--no-headers"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .await
        {
            Ok(output) => output,
            Err(_) => return HashMap::new(),
        };

        let stdout = match String::from_utf8(output.stdout) {
            Ok(s) => s,
            Err(_) => return HashMap::new(),
        };

        let mut infos = HashMap::new();

        for line in stdout.lines() {
            // Split into PID and user
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() != 3 {
                continue;
            }

            let pid: u32 = match parts[0].parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            let user = parts[1].to_string();

            let command = parts[2].to_string();
            let command = if command.len() > 200 {
                format!("{}...", &command[..200])
            } else {
                command.to_string()
            };

            let info = LinuxProcessInfo { user, command };
            infos.insert(pid, info);
        }

        infos
    }

    /// Parse ss output into PortInfo objects.
    ///
    /// Expected ss output format:
    /// ```text
    /// State      Recv-Q     Send-Q              Local Address:Port          Peer Address:Port     Process
    /// LISTEN     0          4096           [::ffff:127.0.0.1]:63342                    *:*         users:(("rustrover",pid=53561,fd=54))
    /// ```
    fn parse_ss_output(&self, output: &str, process_infos: &HashMap<u32, LinuxProcessInfo>) -> Vec<PortInfo> {
        let mut ports = Vec::new();
        let mut seen: HashSet<(u16, u32)> = HashSet::new();

        for line in output.lines() {
            if line.is_empty() {
                continue;
            }

            // Parse columns: [State] [Recv-Q] [Send-Q] [Local Address:Port] [Peer Address:Port] [Process]
            let components: Vec<&str> = line.split_whitespace().collect();
            if components.len() < 6 {
                continue;
            }

            let regex = Regex::new(r#"users:\(\("(.+?)",pid=(\d*),fd=(.+?)\)"#).unwrap();
            let Some(caps) = regex.captures(components[5]) else {
                continue;
            };

            // Extract process name
            let process_name = caps[1].to_string();

            // Parse PID
            let pid: u32 = match caps[2].parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            // Get process info from pid
            let Some(info) = process_infos.get(&pid) else {
                continue;
            };

            let user = info.user.clone();
            let fd = caps[2].to_string();

            // Get full command from process info
            let command = info.command.clone();

            // Parse address and port
            let (address, port) = match Utils::parse_address(&components[3]) {
                Some((a, p)) => (a, p),
                None => continue,
            };

            // Deduplicate by (port, pid)
            if !seen.insert((port, pid)) {
                continue;
            }

            ports.push(PortInfo::active(
                port,
                pid,
                process_name,
                address,
                user,
                command,
                fd,
            ));
        }

        // Sort by port number
        ports.sort_by_key(|p| p.port);
        ports
    }
}

impl Default for LinuxScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl Scanner for LinuxScanner {
    /// Scan all listening TCP ports.
    ///
    /// Executes: `ss -Htlnp`
    ///
    /// Flags explained:
    /// -H, --no-header     Suppress header line
    /// -t, --tcp           display only TCP sockets
    /// -l, --listening     display listening sockets
    /// -n, --numeric       don't resolve service names
    /// -p, --processes     show process using socket
    async fn scan(&self) -> Result<Vec<PortInfo>> {
        let output = Command::new("/usr/sbin/ss")
            .args(["-Htlnp"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .await
            .map_err(|e| Error::CommandFailed(format!("Failed to run ss: {}", e)))?;

        let stdout = String::from_utf8(output.stdout)
            .map_err(|e| Error::ParseError(format!("Invalid UTF-8 in ss output: {}", e)))?;

        let process_infos = self.get_process_infos().await;

        Ok(self.parse_ss_output(&stdout, &process_infos))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_ss_output() {
        let scanner = LinuxScanner::new();
        let mut commands = HashMap::new();
        commands.insert(55316, LinuxProcessInfo {
            user: "user".to_string(),
            command: "nginx".to_string(),
        });
        commands.insert(53561, LinuxProcessInfo {
            user: "user".to_string(),
            command: "node".to_string(),
        });

        let output = r#"LISTEN 0 4096 [::ffff:127.0.0.1]:80 *:* users:(("nginx",pid=55316,fd=6))
LISTEN 0 50 [::ffff:127.0.0.1]:3000 *:* users:(("node",pid=53561,fd=187))"#;

        let ports = scanner.parse_ss_output(output, &commands);
        assert_eq!(ports.len(), 2);

        // Should be sorted by port
        assert_eq!(ports[0].port, 80);
        assert_eq!(ports[0].process_name, "nginx");

        assert_eq!(ports[1].port, 3000);
        assert_eq!(ports[1].process_name, "node");
    }

    #[test]
    fn test_deduplication() {
        let scanner = LinuxScanner::new();
        let mut commands = HashMap::new();
        commands.insert(1234, LinuxProcessInfo {
            user: "user".to_string(),
            command: "code linux.rs".to_string(),
        });

        // Same port and PID should be deduplicated
        let output = r#"LISTEN 0 4096 127.0.0.1:3000 :* users:(("code",pid=1234,fd=54))
LISTEN 0 4096 [::ffff:127.0.0.1]:3000 *:* users:(("code",pid=1234,fd=54))"#;

        let ports = scanner.parse_ss_output(output, &commands);
        assert_eq!(ports.len(), 1);
    }
}
