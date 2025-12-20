//! macOS port scanner implementation using lsof and ps.

use std::collections::{HashMap, HashSet};
use std::process::Stdio;

use tokio::process::Command;

use crate::domain::PortInfo;
use crate::error::{Error, Result};

use super::utils::Utils;
use super::Scanner;

/// macOS-specific port scanner using lsof.
pub struct DarwinScanner;

impl DarwinScanner {
    /// Create a new macOS scanner.
    pub fn new() -> Self {
        Self
    }

    /// Get full command information for all processes using ps.
    async fn get_process_commands(&self) -> HashMap<u32, String> {
        let output = match Command::new("/bin/ps")
            .args(["-axo", "pid,command"])
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

        let mut commands = HashMap::new();

        for line in stdout.lines().skip(1) {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            let mut parts = trimmed.splitn(2, char::is_whitespace);
            let pid_str = match parts.next() {
                Some(s) => s.trim(),
                None => continue,
            };
            let command = match parts.next() {
                Some(s) => s.trim(),
                None => continue,
            };

            let pid: u32 = match pid_str.parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            let command = if command.len() > 200 {
                format!("{}...", &command[..200])
            } else {
                command.to_string()
            };

            commands.insert(pid, command);
        }

        commands
    }

    /// Parse lsof output into PortInfo objects.
    fn parse_lsof_output(&self, output: &str, commands: &HashMap<u32, String>) -> Vec<PortInfo> {
        let mut ports = Vec::new();
        let mut seen: HashSet<(u16, u32)> = HashSet::new();

        for line in output.lines().skip(1) {
            if line.is_empty() {
                continue;
            }

            let components: Vec<&str> = line.split_whitespace().collect();
            if components.len() < 9 {
                continue;
            }

            let mut process_name = components[0].to_string();
            process_name = process_name
                .replace("\\x20", " ")
                .replace("\\x2f", "/");

            let pid: u32 = match components[1].parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            let user = components[2].to_string();
            let fd = components[3].to_string();

            let mut address_part = String::new();
            for i in (8..components.len()).rev() {
                let comp = components[i];
                if comp.contains(':') && !comp.starts_with("0x") && !comp.starts_with("0t") {
                    address_part = comp.to_string();
                    break;
                }
            }

            if address_part.is_empty() {
                continue;
            }

            let command = commands
                .get(&pid)
                .cloned()
                .unwrap_or_else(|| process_name.clone());

            let (address, port) = match Utils::parse_address(&address_part) {
                Some((a, p)) => (a, p),
                None => continue,
            };

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

        ports.sort_by_key(|p| p.port);
        ports
    }
}

impl Default for DarwinScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl Scanner for DarwinScanner {
    async fn scan(&self) -> Result<Vec<PortInfo>> {
        let output = Command::new("/usr/sbin/lsof")
            .args(["-iTCP", "-sTCP:LISTEN", "-P", "-n", "+c", "0"])
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .output()
            .await
            .map_err(|e| Error::CommandFailed(format!("Failed to run lsof: {}", e)))?;

        let stdout = String::from_utf8(output.stdout)
            .map_err(|e| Error::ParseError(format!("Invalid UTF-8 in lsof output: {}", e)))?;

        let commands = self.get_process_commands().await;
        Ok(self.parse_lsof_output(&stdout, &commands))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_lsof_output() {
        let scanner = DarwinScanner::new();
        let commands = HashMap::new();

        let output = r#"COMMAND    PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
node     34805  code   19u  IPv6 0x3d8015e195af1f3f      0t0  TCP [::1]:3000 (LISTEN)
nginx        1  root    6u  IPv4 0x1234567890abcdef      0t0  TCP *:80 (LISTEN)
"#;

        let ports = scanner.parse_lsof_output(output, &commands);
        assert_eq!(ports.len(), 2);
        assert_eq!(ports[0].port, 80);
        assert_eq!(ports[1].port, 3000);
    }
}
