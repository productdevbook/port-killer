//! Linux port scanner implementation using ss.

use std::collections::{HashMap, HashSet};
use std::process::Stdio;

use regex::Regex;
use tokio::process::Command;

use crate::domain::PortInfo;
use crate::error::{Error, Result};

use super::utils::Utils;
use super::Scanner;

/// Linux-specific port scanner.
pub struct LinuxScanner;

struct LinuxProcessInfo {
    user: String,
    command: String,
}

impl LinuxScanner {
    pub fn new() -> Self {
        Self
    }

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
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() < 3 {
                continue;
            }

            let pid: u32 = match parts[0].parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            let user = parts[1].to_string();
            let command = parts[2..].join(" ");
            let command = if command.len() > 200 {
                format!("{}...", &command[..200])
            } else {
                command
            };

            infos.insert(pid, LinuxProcessInfo { user, command });
        }

        infos
    }

    fn parse_ss_output(
        &self,
        output: &str,
        process_infos: &HashMap<u32, LinuxProcessInfo>,
    ) -> Vec<PortInfo> {
        let mut ports = Vec::new();
        let mut seen: HashSet<(u16, u32)> = HashSet::new();

        let regex = Regex::new(r#"users:\(\("(.+?)",pid=(\d+),fd=(\d+)\)"#).unwrap();

        for line in output.lines() {
            if line.is_empty() {
                continue;
            }

            let components: Vec<&str> = line.split_whitespace().collect();
            if components.len() < 6 {
                continue;
            }

            let Some(caps) = regex.captures(components[5]) else {
                continue;
            };

            let process_name = caps[1].to_string();
            let pid: u32 = match caps[2].parse() {
                Ok(p) => p,
                Err(_) => continue,
            };

            let info = process_infos.get(&pid);
            let user = info.map(|i| i.user.clone()).unwrap_or_default();
            let command = info.map(|i| i.command.clone()).unwrap_or_else(|| process_name.clone());
            let fd = caps[3].to_string();

            let (address, port) = match Utils::parse_address(components[3]) {
                Some((a, p)) => (a, p),
                None => continue,
            };

            if !seen.insert((port, pid)) {
                continue;
            }

            ports.push(PortInfo::active(port, pid, process_name, address, user, command, fd));
        }

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
