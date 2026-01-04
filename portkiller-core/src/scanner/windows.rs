//! Windows port scanner implementation
//!
//! Uses `netstat -ano` to get listening ports and `tasklist /FO CSV` to resolve process names.

#![cfg(target_os = "windows")]

use std::collections::{HashMap, HashSet};
use tokio::process::Command;

use crate::models::PortInfo;
use crate::scanner::{PortScanner, ScanError};

/// Windows-specific port scanner using netstat and tasklist
pub struct WindowsScanner;

impl WindowsScanner {
    /// Create a new WindowsScanner
    pub fn new() -> Self {
        Self
    }

    /// Get PIDs of processes using a specific port
    ///
    /// Uses `netstat -ano` to find processes listening on the specified port.
    ///
    /// Returns a list of PIDs using the specified port.
    pub async fn get_pids_on_port(&self, port: u16) -> Result<Vec<u32>, ScanError> {
        let output = Self::run_netstat().await?;
        let all_ports = Self::parse_netstat_output(&output);

        let pids: Vec<u32> = all_ports
            .into_iter()
            .filter(|(p, _, _)| *p == port)
            .map(|(_, pid, _)| pid)
            .collect();

        Ok(pids)
    }

    /// Parse the output of `netstat -ano` to extract listening TCP ports
    ///
    /// Example output:
    /// ```text
    /// Active Connections
    ///
    ///   Proto  Local Address          Foreign Address        State           PID
    ///   TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       1020
    ///   TCP    [::]:445               [::]:0                 LISTENING       4
    ///   TCP    127.0.0.1:3000         0.0.0.0:0              LISTENING       5432
    /// ```
    fn parse_netstat_output(output: &str) -> Vec<(u16, u32, String)> {
        let mut results = Vec::new();
        let mut seen: HashSet<(u16, u32)> = HashSet::new();

        for line in output.lines() {
            let line = line.trim();

            // Skip empty lines and headers
            if line.is_empty() || line.starts_with("Active") || line.starts_with("Proto") {
                continue;
            }

            // Parse TCP lines only (skip UDP)
            if !line.starts_with("TCP") {
                continue;
            }

            // Split by whitespace
            let parts: Vec<&str> = line.split_whitespace().collect();

            // Expected format: TCP, Local Address, Foreign Address, State, PID
            if parts.len() < 5 {
                continue;
            }

            // Only interested in LISTENING state
            if parts[3] != "LISTENING" {
                continue;
            }

            // Parse local address (can be IPv4 or IPv6)
            let local_addr = parts[1];
            let (address, port) = match Self::parse_address(local_addr) {
                Some(parsed) => parsed,
                None => continue,
            };

            // Parse PID
            let pid: u32 = match parts[4].parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            // Deduplicate by (port, pid)
            if seen.insert((port, pid)) {
                results.push((port, pid, address));
            }
        }

        results
    }

    /// Parse an address string like "0.0.0.0:135" or "[::]:445" or "127.0.0.1:3000"
    /// Returns (address_without_port, port)
    fn parse_address(addr: &str) -> Option<(String, u16)> {
        // Handle IPv6 format: [::]:port or [::1]:port
        if addr.starts_with('[') {
            // Find the closing bracket
            let bracket_end = addr.find(']')?;
            let ipv6_addr = &addr[1..bracket_end];

            // Port comes after ]:
            if addr.len() > bracket_end + 2 && addr.chars().nth(bracket_end + 1)? == ':' {
                let port_str = &addr[bracket_end + 2..];
                let port: u16 = port_str.parse().ok()?;
                return Some((ipv6_addr.to_string(), port));
            }
            return None;
        }

        // Handle IPv4 format: addr:port
        // Find the last colon (in case of malformed data)
        let colon_pos = addr.rfind(':')?;
        let ip = &addr[..colon_pos];
        let port_str = &addr[colon_pos + 1..];
        let port: u16 = port_str.parse().ok()?;

        // Convert 0.0.0.0 to * for display consistency
        let address = if ip == "0.0.0.0" {
            "*".to_string()
        } else {
            ip.to_string()
        };

        Some((address, port))
    }

    /// Parse the output of `tasklist /FO CSV` to get a PID -> process name mapping
    ///
    /// Example output:
    /// ```text
    /// "Image Name","PID","Session Name","Session#","Mem Usage"
    /// "System Idle Process","0","Services","0","8 K"
    /// "node.exe","5432","Console","1","45,000 K"
    /// ```
    fn parse_tasklist_output(output: &str) -> HashMap<u32, String> {
        let mut map = HashMap::new();

        for line in output.lines() {
            let line = line.trim();

            // Skip empty lines and header
            if line.is_empty() || line.starts_with("\"Image Name\"") {
                continue;
            }

            // Parse CSV format: "name","pid",...
            let fields: Vec<&str> = Self::parse_csv_line(line);

            if fields.len() < 2 {
                continue;
            }

            let process_name = fields[0].to_string();
            let pid: u32 = match fields[1].parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            // Remove .exe extension for cleaner display
            let clean_name = process_name
                .strip_suffix(".exe")
                .unwrap_or(&process_name)
                .to_string();

            map.insert(pid, clean_name);
        }

        map
    }

    /// Parse a CSV line, handling quoted fields
    fn parse_csv_line(line: &str) -> Vec<&str> {
        let mut fields = Vec::new();
        let mut chars = line.char_indices().peekable();
        let mut in_quotes = false;
        let mut field_start: Option<usize> = None;

        while let Some((i, c)) = chars.next() {
            match c {
                '"' => {
                    if in_quotes {
                        // End of quoted field
                        if let Some(start) = field_start {
                            fields.push(&line[start..i]);
                        }
                        field_start = None;
                        in_quotes = false;
                    } else {
                        // Start of quoted field
                        in_quotes = true;
                        field_start = Some(i + 1);
                    }
                }
                ',' => {
                    if !in_quotes {
                        // Field separator outside quotes
                        if let Some(start) = field_start {
                            fields.push(&line[start..i]);
                            field_start = None;
                        }
                    }
                }
                _ => {
                    if field_start.is_none() && !in_quotes {
                        field_start = Some(i);
                    }
                }
            }
        }

        // Handle last field if not in quotes
        if let Some(start) = field_start {
            if !in_quotes {
                fields.push(&line[start..]);
            }
        }

        fields
    }

    /// Run netstat command and return output
    async fn run_netstat() -> Result<String, ScanError> {
        let output = Command::new("netstat")
            .args(["-ano"])
            .output()
            .await
            .map_err(|e| ScanError::CommandError(format!("netstat -ano: {}", e)))?;

        if !output.status.success() {
            return Err(ScanError::CommandError(format!(
                "netstat -ano failed: {}",
                String::from_utf8_lossy(&output.stderr)
            )));
        }

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }

    /// Run tasklist command and return output
    async fn run_tasklist() -> Result<String, ScanError> {
        let output = Command::new("tasklist")
            .args(["/FO", "CSV"])
            .output()
            .await
            .map_err(|e| ScanError::CommandError(format!("tasklist /FO CSV: {}", e)))?;

        if !output.status.success() {
            return Err(ScanError::CommandError(format!(
                "tasklist /FO CSV failed: {}",
                String::from_utf8_lossy(&output.stderr)
            )));
        }

        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }
}

impl Default for WindowsScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl PortScanner for WindowsScanner {
    async fn scan_ports(&self) -> Result<Vec<PortInfo>, ScanError> {
        // Run netstat and tasklist in parallel for better performance
        let (netstat_result, tasklist_result) =
            tokio::join!(Self::run_netstat(), Self::run_tasklist());

        let netstat_output = netstat_result?;
        let tasklist_output = tasklist_result?;

        // Parse outputs
        let ports = Self::parse_netstat_output(&netstat_output);
        let process_names = Self::parse_tasklist_output(&tasklist_output);

        // Build PortInfo list
        let mut results = Vec::new();
        for (port, pid, address) in ports {
            let process_name = process_names
                .get(&pid)
                .cloned()
                .unwrap_or_else(|| format!("PID {}", pid));

            // For Windows, we don't have easy access to full command line
            // Use process name as command for now
            let command = process_name.clone();

            results.push(PortInfo::new(port, pid, process_name, command, address));
        }

        // Sort by port number
        results.sort_by_key(|p| p.port);

        Ok(results)
    }
}

#[cfg(test)]
#[cfg(target_os = "windows")]
mod tests {
    use super::*;

    #[test]
    fn test_parse_netstat_output() {
        let output = r#"
Active Connections

  Proto  Local Address          Foreign Address        State           PID
  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       1020
  TCP    0.0.0.0:445            0.0.0.0:0              LISTENING       4
  TCP    127.0.0.1:3000         0.0.0.0:0              LISTENING       5432
  TCP    [::]:135               [::]:0                 LISTENING       1020
  TCP    [::]:445               [::]:0                 LISTENING       4
  TCP    [::1]:6379             [::]:0                 LISTENING       8080
"#;
        let results = WindowsScanner::parse_netstat_output(output);

        // Should have 6 entries (no deduplication by port+pid across IPv4/IPv6)
        assert_eq!(results.len(), 6);

        // Check first entry
        assert!(results.iter().any(|(port, pid, addr)| *port == 135 && *pid == 1020 && addr == "*"));

        // Check IPv6 entry
        assert!(results.iter().any(|(port, pid, addr)| *port == 6379 && *pid == 8080 && addr == "::1"));
    }

    #[test]
    fn test_parse_address_ipv4() {
        assert_eq!(
            WindowsScanner::parse_address("0.0.0.0:135"),
            Some(("*".to_string(), 135))
        );
        assert_eq!(
            WindowsScanner::parse_address("127.0.0.1:3000"),
            Some(("127.0.0.1".to_string(), 3000))
        );
        assert_eq!(
            WindowsScanner::parse_address("192.168.1.1:8080"),
            Some(("192.168.1.1".to_string(), 8080))
        );
    }

    #[test]
    fn test_parse_address_ipv6() {
        assert_eq!(
            WindowsScanner::parse_address("[::]:445"),
            Some(("::".to_string(), 445))
        );
        assert_eq!(
            WindowsScanner::parse_address("[::1]:6379"),
            Some(("::1".to_string(), 6379))
        );
        assert_eq!(
            WindowsScanner::parse_address("[fe80::1]:8080"),
            Some(("fe80::1".to_string(), 8080))
        );
    }

    #[test]
    fn test_parse_tasklist_output() {
        let output = r#"
"Image Name","PID","Session Name","Session#","Mem Usage"
"System Idle Process","0","Services","0","8 K"
"System","4","Services","0","144 K"
"node.exe","5432","Console","1","45,000 K"
"postgres.exe","1234","Services","0","32,768 K"
"#;
        let map = WindowsScanner::parse_tasklist_output(output);

        assert_eq!(map.get(&0), Some(&"System Idle Process".to_string()));
        assert_eq!(map.get(&4), Some(&"System".to_string()));
        assert_eq!(map.get(&5432), Some(&"node".to_string()));
        assert_eq!(map.get(&1234), Some(&"postgres".to_string()));
    }

    #[test]
    fn test_parse_csv_line() {
        let line = r#""node.exe","5432","Console","1","45,000 K""#;
        let fields = WindowsScanner::parse_csv_line(line);

        assert_eq!(fields.len(), 5);
        assert_eq!(fields[0], "node.exe");
        assert_eq!(fields[1], "5432");
        assert_eq!(fields[2], "Console");
        assert_eq!(fields[3], "1");
        assert_eq!(fields[4], "45,000 K");
    }

    #[test]
    fn test_deduplication() {
        // Same port+pid should only appear once
        let output = r#"
Active Connections

  Proto  Local Address          Foreign Address        State           PID
  TCP    0.0.0.0:3000           0.0.0.0:0              LISTENING       1234
  TCP    0.0.0.0:3000           0.0.0.0:0              LISTENING       1234
"#;
        let results = WindowsScanner::parse_netstat_output(output);
        assert_eq!(results.len(), 1);
    }
}
