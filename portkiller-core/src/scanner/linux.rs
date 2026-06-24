//! Linux-specific port scanner implementation
//!
//! Uses `lsof` as the primary scanner and falls back to `ss` if `lsof` is not installed.
//! Process names and full commands are enriched using `ps`.

use std::collections::{HashMap, HashSet};
use tokio::process::Command;
use crate::models::PortInfo;
use super::{PortScanner, ScanError};

/// Linux port scanner implementation
#[derive(Debug, Default)]
pub struct LinuxScanner;

impl LinuxScanner {
    /// Create a new LinuxScanner instance
    pub fn new() -> Self {
        Self
    }

    /// Get PIDs of processes using a specific port
    ///
    /// Tries `lsof -ti tcp:<port>` first, and falls back to `ss` if `lsof` is not available.
    pub async fn get_pids_on_port(&self, port: u16) -> Result<Vec<u32>, ScanError> {
        // Try lsof first
        match Command::new("lsof")
            .args(["-ti", &format!("tcp:{}", port)])
            .output()
            .await
        {
            Ok(output) => {
                if output.status.success() || !output.stdout.is_empty() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    let pids: Vec<u32> = stdout
                        .lines()
                        .filter_map(|line| line.trim().parse().ok())
                        .collect();
                    return Ok(pids);
                }
            }
            Err(_) => {
                // lsof command probably not found, fall back to ss
            }
        }

        // Fallback to ss
        self.get_pids_on_port_ss(port).await
    }

    /// Fallback implementation to get PIDs using ss
    async fn get_pids_on_port_ss(&self, port: u16) -> Result<Vec<u32>, ScanError> {
        let output = Command::new("ss")
            .args(["-tlnp"])
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ScanError::CommandError(format!("ss failed: {}", stderr)));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut pids = Vec::new();

        for line in stdout.lines() {
            if line.is_empty() {
                continue;
            }

            let columns: Vec<&str> = line.split_whitespace().collect();
            if columns.len() < 4 {
                continue;
            }

            // Local address is in column 3 (0-indexed)
            let local_addr = columns[3];
            let last_colon = match local_addr.rfind(':') {
                Some(idx) => idx,
                None => continue,
            };
            let port_str = &local_addr[last_colon + 1..];
            let line_port: u16 = match port_str.parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            if line_port == port && columns.len() >= 6 {
                // Process info is in the last column
                let proc_col = columns[5];
                for (_, pid) in Self::parse_ss_users(proc_col) {
                    pids.push(pid);
                }
            }
        }

        pids.sort();
        pids.dedup();
        Ok(pids)
    }

    /// Get full command line information for all processes using `ps`
    ///
    /// Executes: `ps -axo pid,command`
    async fn get_process_commands(&self) -> Result<HashMap<u32, String>, ScanError> {
        let output = Command::new("ps")
            .args(["-axo", "pid,command"])
            .output()
            .await?;

        if !output.status.success() {
            return Err(ScanError::CommandError(format!(
                "ps failed with status: {}",
                output.status
            )));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let mut commands = HashMap::new();

        // Skip header line
        for line in stdout.lines().skip(1) {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            // Parse "PID COMMAND" format
            let parts: Vec<&str> = trimmed.splitn(2, ' ').collect();
            if parts.len() < 2 {
                continue;
            }

            let pid_str = parts[0].trim();
            let pid: u32 = match pid_str.parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            let full_command = parts[1].trim();
            let command = if full_command.len() > 200 {
                format!("{}...", &full_command[..200])
            } else {
                full_command.to_string()
            };

            commands.insert(pid, command);
        }

        Ok(commands)
    }

    /// Decode escaped characters in lsof output (e.g. `\x20` -> space)
    fn decode_escaped(input: &str) -> String {
        let mut result = String::with_capacity(input.len());
        let mut chars = input.chars().peekable();

        while let Some(c) = chars.next() {
            if c == '\\' {
                if chars.peek() == Some(&'x') {
                    chars.next(); // consume 'x'

                    let mut hex = String::with_capacity(2);
                    for _ in 0..2 {
                        if let Some(&c) = chars.peek() {
                            if c.is_ascii_hexdigit() {
                                hex.push(chars.next().unwrap());
                            } else {
                                break;
                            }
                        }
                    }

                    if hex.len() == 2 {
                        if let Ok(byte) = u8::from_str_radix(&hex, 16) {
                            result.push(byte as char);
                            continue;
                        }
                    }

                    result.push('\\');
                    result.push('x');
                    result.push_str(&hex);
                } else {
                    result.push(c);
                }
            } else {
                result.push(c);
            }
        }

        result
    }

    /// Parse an address:port string into (address, port)
    fn parse_address(address: &str) -> Option<(String, u16)> {
        if address.starts_with('[') {
            let bracket_end = address.find(']')?;
            if bracket_end + 1 >= address.len() {
                return None;
            }

            let after_bracket = &address[bracket_end + 1..];
            if !after_bracket.starts_with(':') {
                return None;
            }

            let addr = address[..=bracket_end].to_string();
            let port_str = &after_bracket[1..];
            let port: u16 = port_str.parse().ok()?;

            Some((addr, port))
        } else {
            let last_colon = address.rfind(':')?;
            let addr = &address[..last_colon];
            let port_str = &address[last_colon + 1..];
            let port: u16 = port_str.parse().ok()?;

            let addr = if addr.is_empty() { "*" } else { addr };
            Some((addr.to_string(), port))
        }
    }

    /// Parse users from ss output process column (e.g. `users:(("nginx",pid=1234,fd=5))`)
    fn parse_ss_users(users_str: &str) -> Vec<(String, u32)> {
        let mut results = Vec::new();
        if let Some(start_idx) = users_str.find("users:(") {
            let content = &users_str[start_idx + 7..users_str.len() - 1];
            for part in content.split("),(") {
                let clean_part = part.trim_start_matches('(').trim_end_matches(')');
                let fields: Vec<&str> = clean_part.split(',').collect();
                if fields.len() >= 2 {
                    let process_name = fields[0].trim_matches('"').to_string();
                    let pid_str = fields[1].trim();
                    if pid_str.starts_with("pid=") {
                        if let Ok(pid) = pid_str[4..].parse::<u32>() {
                            results.push((process_name, pid));
                        }
                    }
                }
            }
        }
        results
    }

    /// Parse lsof output into PortInfo objects
    fn parse_lsof_output(
        output: &str,
        commands: &HashMap<u32, String>,
    ) -> Result<Vec<PortInfo>, ScanError> {
        let mut ports = Vec::new();
        let mut seen = HashSet::new();

        for line in output.lines().skip(1) {
            if line.is_empty() {
                continue;
            }

            let columns: Vec<&str> = line.split_whitespace().collect();
            if columns.len() < 9 {
                continue;
            }

            let process_name = Self::decode_escaped(columns[0]);
            let pid: u32 = match columns[1].parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            let mut address_part = None;
            for i in (8..columns.len()).rev() {
                let col = columns[i];
                if col.contains(':') && !col.starts_with("0x") && !col.starts_with("0t") {
                    address_part = Some(col);
                    break;
                }
            }

            let address_str = match address_part {
                Some(a) => a,
                None => continue,
            };

            let (address, port) = match Self::parse_address(address_str) {
                Some((a, p)) => (a, p),
                None => continue,
            };

            let command = commands.get(&pid).cloned().unwrap_or_else(|| process_name.clone());

            if !seen.insert((port, pid)) {
                continue;
            }

            ports.push(PortInfo::new(port, pid, process_name, command, address));
        }

        ports.sort_by_key(|p| p.port);
        Ok(ports)
    }

    /// Parse ss output into PortInfo objects
    fn parse_ss_output(
        &self,
        output: &str,
        commands: &HashMap<u32, String>,
    ) -> Vec<PortInfo> {
        let mut ports = Vec::new();
        let mut seen = HashSet::new();

        for line in output.lines() {
            if line.is_empty() {
                continue;
            }

            let columns: Vec<&str> = line.split_whitespace().collect();
            if columns.len() < 4 {
                continue;
            }

            // Local address is in column 3 (0-indexed)
            let local_addr = columns[3];
            let last_colon = match local_addr.rfind(':') {
                Some(idx) => idx,
                None => continue,
            };
            let port_str = &local_addr[last_colon + 1..];
            let port: u16 = match port_str.parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            let address = &local_addr[..last_colon];
            let address = if address.is_empty() { "*" } else { address };

            // Check if process column (5) exists
            if columns.len() >= 6 {
                let proc_col = columns[5];
                let users = Self::parse_ss_users(proc_col);
                if users.is_empty() {
                    // Fallback to active port without process info
                    if seen.insert((port, 0)) {
                        ports.push(PortInfo::new(
                            port,
                            0,
                            "Unknown".to_string(),
                            "Unknown".to_string(),
                            address.to_string(),
                        ));
                    }
                } else {
                    for (process_name, pid) in users {
                        if !seen.insert((port, pid)) {
                            continue;
                        }

                        let command = commands.get(&pid).cloned().unwrap_or_else(|| process_name.clone());
                        ports.push(PortInfo::new(port, pid, process_name, command, address.to_string()));
                    }
                }
            } else {
                // No process info available
                if seen.insert((port, 0)) {
                    ports.push(PortInfo::new(
                        port,
                        0,
                        "Unknown".to_string(),
                        "Unknown".to_string(),
                        address.to_string(),
                    ));
                }
            }
        }

        ports.sort_by_key(|p| p.port);
        ports
    }
}

impl PortScanner for LinuxScanner {
    async fn scan_ports(&self) -> Result<Vec<PortInfo>, ScanError> {
        let commands = self.get_process_commands().await.unwrap_or_default();

        // Try lsof first
        match Command::new("lsof")
            .args(["-iTCP", "-sTCP:LISTEN", "-P", "-n", "+c", "0"])
            .output()
            .await
        {
            Ok(output) => {
                if output.status.success() || !output.stdout.is_empty() {
                    let stdout = String::from_utf8_lossy(&output.stdout);
                    if !stdout.is_empty() {
                        return Self::parse_lsof_output(&stdout, &commands);
                    }
                }
            }
            Err(_) => {
                // lsof probably not installed, fall back to ss
            }
        }

        // Fall back to ss
        let output = Command::new("ss")
            .args(["-tlnp"])
            .output()
            .await?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ScanError::CommandError(format!("ss failed: {}", stderr)));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        Ok(self.parse_ss_output(&stdout, &commands))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_ss_users_single() {
        let input = "users:((\"github-desktop\",pid=19282,fd=49))";
        let res = LinuxScanner::parse_ss_users(input);
        assert_eq!(res.len(), 1);
        assert_eq!(res[0].0, "github-desktop");
        assert_eq!(res[0].1, 19282);
    }

    #[test]
    fn test_parse_ss_users_multiple() {
        let input = "users:((\"nginx\",pid=1234,fd=5),(\"nginx\",pid=1235,fd=5))";
        let res = LinuxScanner::parse_ss_users(input);
        assert_eq!(res.len(), 2);
        assert_eq!(res[0].0, "nginx");
        assert_eq!(res[0].1, 1234);
        assert_eq!(res[1].0, "nginx");
        assert_eq!(res[1].1, 1235);
    }

    #[test]
    fn test_parse_address_ipv4() {
        assert_eq!(
            LinuxScanner::parse_address("127.0.0.1:3000"),
            Some(("127.0.0.1".to_string(), 3000))
        );
        assert_eq!(
            LinuxScanner::parse_address("*:8080"),
            Some(("*".to_string(), 8080))
        );
        assert_eq!(
            LinuxScanner::parse_address("0.0.0.0:443"),
            Some(("0.0.0.0".to_string(), 443))
        );
    }

    #[test]
    fn test_parse_address_ipv6() {
        assert_eq!(
            LinuxScanner::parse_address("[::1]:3000"),
            Some(("[::1]".to_string(), 3000))
        );
        assert_eq!(
            LinuxScanner::parse_address("[fe80::1]:8080"),
            Some(("[fe80::1]".to_string(), 8080))
        );
    }
}
