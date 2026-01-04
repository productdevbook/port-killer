//! macOS port scanner implementation
//!
//! Uses `lsof` to find listening TCP ports and `ps` to get full command information.

use super::{PortScanner, ScanError};
use crate::models::PortInfo;
use std::collections::{HashMap, HashSet};
use tokio::process::Command;

/// macOS port scanner using lsof and ps commands
#[derive(Debug, Default)]
pub struct MacOsScanner;

impl MacOsScanner {
    /// Create a new macOS scanner
    pub fn new() -> Self {
        Self
    }

    /// Get PIDs of processes using a specific port
    ///
    /// Executes: `lsof -ti tcp:<port>`
    ///
    /// Flags:
    /// - -t: Terse output (PIDs only)
    /// - -i tcp:<port>: Filter by TCP port
    ///
    /// Returns a list of PIDs using the specified port.
    pub async fn get_pids_on_port(&self, port: u16) -> Result<Vec<u32>, ScanError> {
        let output = Command::new("/usr/sbin/lsof")
            .args(["-ti", &format!("tcp:{}", port)])
            .output()
            .await?;

        // lsof returns exit code 1 when no processes found, which is not an error
        if !output.status.success() && !output.stdout.is_empty() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(ScanError::CommandError(format!("lsof failed: {}", stderr)));
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let pids: Vec<u32> = stdout
            .lines()
            .filter_map(|line| line.trim().parse().ok())
            .collect();

        Ok(pids)
    }

    /// Get full command line information for all processes using `ps`
    ///
    /// Executes: `ps -axo pid,command`
    ///
    /// Returns a map of PID to full command string.
    /// Commands longer than 200 characters are truncated with "...".
    async fn get_process_commands(&self) -> Result<HashMap<u32, String>, ScanError> {
        let output = Command::new("/bin/ps")
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
            // The PID is left-padded with spaces, then a space, then the command
            let parts: Vec<&str> = trimmed.splitn(2, ' ').collect();
            if parts.len() < 2 {
                continue;
            }

            // Parse PID
            let pid_str = parts[0].trim();
            let pid: u32 = match pid_str.parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            // Get command, truncate if too long
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

    /// Decode escaped characters in lsof output
    ///
    /// lsof escapes special characters in process names:
    /// - `\x20` -> space
    /// - `\x2f` -> forward slash
    /// - Other hex escapes like `\xNN`
    fn decode_escaped(input: &str) -> String {
        let mut result = String::with_capacity(input.len());
        let mut chars = input.chars().peekable();

        while let Some(c) = chars.next() {
            if c == '\\' {
                // Check for \xNN hex escape
                if chars.peek() == Some(&'x') {
                    chars.next(); // consume 'x'

                    // Read two hex digits
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

                    // If we couldn't parse it, output as-is
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
    ///
    /// Handles multiple formats:
    /// - IPv4: "127.0.0.1:3000", "*:8080"
    /// - IPv6: "[::1]:3000", "[fe80::1]:8080"
    fn parse_address(address: &str) -> Option<(String, u16)> {
        if address.starts_with('[') {
            // IPv6 format: [::1]:3000
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
            // IPv4 format: 127.0.0.1:3000 or *:8080
            // Find the last colon (in case address contains colons)
            let last_colon = address.rfind(':')?;
            let addr = &address[..last_colon];
            let port_str = &address[last_colon + 1..];
            let port: u16 = port_str.parse().ok()?;

            let addr = if addr.is_empty() { "*" } else { addr };
            Some((addr.to_string(), port))
        }
    }

    /// Parse lsof output into PortInfo objects
    ///
    /// Expected lsof output format:
    /// ```text
    /// COMMAND    PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
    /// node     34805  code   19u  IPv6 0x3d8015e195af1f3f      0t0  TCP [::1]:3000 (LISTEN)
    /// ```
    fn parse_lsof_output(
        output: &str,
        commands: &HashMap<u32, String>,
    ) -> Result<Vec<PortInfo>, ScanError> {
        let mut ports = Vec::new();
        let mut seen: HashSet<(u16, u32)> = HashSet::new();

        // Skip header line
        for line in output.lines().skip(1) {
            if line.is_empty() {
                continue;
            }

            // Split line into columns
            let columns: Vec<&str> = line.split_whitespace().collect();
            if columns.len() < 9 {
                continue;
            }

            // Column 0: COMMAND (process name)
            let process_name = Self::decode_escaped(columns[0]);

            // Column 1: PID
            let pid: u32 = match columns[1].parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            // Find the NAME column (address:port)
            // It's usually near the end, before "(LISTEN)"
            // We search backwards to find a component with ":" that isn't a device ID
            let mut address_part: Option<&str> = None;
            for i in (8..columns.len()).rev() {
                let col = columns[i];
                // Skip device IDs (0x...) and sizes (0t...)
                if col.contains(':') && !col.starts_with("0x") && !col.starts_with("0t") {
                    address_part = Some(col);
                    break;
                }
            }

            let address_str = match address_part {
                Some(a) => a,
                None => continue,
            };

            // Parse address and port
            let (address, port) = match Self::parse_address(address_str) {
                Some((a, p)) => (a, p),
                None => continue,
            };

            // Get full command from ps output, fallback to process name
            let command = commands.get(&pid).cloned().unwrap_or_else(|| process_name.clone());

            // Deduplicate by (port, pid)
            if !seen.insert((port, pid)) {
                continue;
            }

            ports.push(PortInfo::new(port, pid, process_name, command, address));
        }

        // Sort by port number
        ports.sort_by_key(|p| p.port);

        Ok(ports)
    }
}

impl PortScanner for MacOsScanner {
    /// Scan all listening TCP ports using lsof
    ///
    /// Executes: `lsof -iTCP -sTCP:LISTEN -P -n +c 0`
    ///
    /// Flags:
    /// - -iTCP: Show only TCP connections
    /// - -sTCP:LISTEN: Show only listening sockets
    /// - -P: Show port numbers (don't resolve to service names)
    /// - -n: Show IP addresses (don't resolve to hostnames)
    /// - +c 0: Show full command name (unlimited length)
    async fn scan_ports(&self) -> Result<Vec<PortInfo>, ScanError> {
        // Run lsof and ps in parallel
        let lsof_future = Command::new("/usr/sbin/lsof")
            .args(["-iTCP", "-sTCP:LISTEN", "-P", "-n", "+c", "0"])
            .output();

        let ps_future = self.get_process_commands();

        let (lsof_result, commands_result) = tokio::join!(lsof_future, ps_future);

        let lsof_output = lsof_result?;
        let commands = commands_result?;

        // lsof returns exit code 1 when no ports are found, which is not an error
        if !lsof_output.status.success() && !lsof_output.stdout.is_empty() {
            let stderr = String::from_utf8_lossy(&lsof_output.stderr);
            return Err(ScanError::CommandError(format!(
                "lsof failed: {}",
                stderr
            )));
        }

        let stdout = String::from_utf8_lossy(&lsof_output.stdout);
        if stdout.is_empty() {
            return Ok(Vec::new());
        }

        Self::parse_lsof_output(&stdout, &commands)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decode_escaped() {
        assert_eq!(MacOsScanner::decode_escaped("Code\\x20Helper"), "Code Helper");
        assert_eq!(MacOsScanner::decode_escaped("path\\x2fto\\x2ffile"), "path/to/file");
        assert_eq!(MacOsScanner::decode_escaped("no_escapes"), "no_escapes");
        assert_eq!(MacOsScanner::decode_escaped(""), "");
        // Partial escape should be preserved
        assert_eq!(MacOsScanner::decode_escaped("test\\x"), "test\\x");
        assert_eq!(MacOsScanner::decode_escaped("test\\x2"), "test\\x2");
    }

    #[test]
    fn test_parse_address_ipv4() {
        assert_eq!(
            MacOsScanner::parse_address("127.0.0.1:3000"),
            Some(("127.0.0.1".to_string(), 3000))
        );
        assert_eq!(
            MacOsScanner::parse_address("*:8080"),
            Some(("*".to_string(), 8080))
        );
        assert_eq!(
            MacOsScanner::parse_address("0.0.0.0:443"),
            Some(("0.0.0.0".to_string(), 443))
        );
    }

    #[test]
    fn test_parse_address_ipv6() {
        assert_eq!(
            MacOsScanner::parse_address("[::1]:3000"),
            Some(("[::1]".to_string(), 3000))
        );
        assert_eq!(
            MacOsScanner::parse_address("[fe80::1]:8080"),
            Some(("[fe80::1]".to_string(), 8080))
        );
        assert_eq!(
            MacOsScanner::parse_address("[::]:80"),
            Some(("[::]".to_string(), 80))
        );
    }

    #[test]
    fn test_parse_address_invalid() {
        assert_eq!(MacOsScanner::parse_address("invalid"), None);
        assert_eq!(MacOsScanner::parse_address("no:port:here"), None); // port "here" is not a number
        assert_eq!(MacOsScanner::parse_address("[::1]"), None); // missing port
        assert_eq!(MacOsScanner::parse_address("[::1]3000"), None); // missing colon after bracket
    }

    #[test]
    fn test_parse_lsof_output() {
        let lsof_output = r#"COMMAND    PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
node     34805  code   19u  IPv6 0x3d8015e195af1f3f      0t0  TCP [::1]:3000 (LISTEN)
nginx     1234  root    5u  IPv4 0x1234567890abcdef      0t0  TCP *:80 (LISTEN)
Code\x20Helper  5678  user   10u  IPv4 0xabcdef1234567890      0t0  TCP 127.0.0.1:8080 (LISTEN)"#;

        let mut commands = HashMap::new();
        commands.insert(34805, "node /path/to/server.js".to_string());
        commands.insert(1234, "/usr/sbin/nginx -g daemon off".to_string());
        commands.insert(5678, "/Applications/Code.app/Contents/Helpers/Code Helper".to_string());

        let result = MacOsScanner::parse_lsof_output(lsof_output, &commands).unwrap();

        assert_eq!(result.len(), 3);

        // Results should be sorted by port
        assert_eq!(result[0].port, 80);
        assert_eq!(result[0].pid, 1234);
        assert_eq!(result[0].process_name, "nginx");
        assert_eq!(result[0].address, "*");

        assert_eq!(result[1].port, 3000);
        assert_eq!(result[1].pid, 34805);
        assert_eq!(result[1].process_name, "node");
        assert_eq!(result[1].address, "[::1]");
        assert_eq!(result[1].command, "node /path/to/server.js");

        assert_eq!(result[2].port, 8080);
        assert_eq!(result[2].pid, 5678);
        assert_eq!(result[2].process_name, "Code Helper"); // Decoded
        assert_eq!(result[2].address, "127.0.0.1");
    }

    #[test]
    fn test_parse_lsof_deduplication() {
        // Same port+pid should be deduplicated
        let lsof_output = r#"COMMAND    PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
node     34805  code   19u  IPv6 0x3d8015e195af1f3f      0t0  TCP [::1]:3000 (LISTEN)
node     34805  code   20u  IPv4 0x1234567890abcdef      0t0  TCP 127.0.0.1:3000 (LISTEN)"#;

        let commands = HashMap::new();
        let result = MacOsScanner::parse_lsof_output(lsof_output, &commands).unwrap();

        // Should only have one entry (first one wins)
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].port, 3000);
        assert_eq!(result[0].pid, 34805);
    }

    #[tokio::test]
    async fn test_scanner_integration() {
        // This test actually runs the scanner - only works on macOS
        if cfg!(target_os = "macos") {
            let scanner = MacOsScanner::new();
            let result = scanner.scan_ports().await;
            assert!(result.is_ok());
        }
    }
}
