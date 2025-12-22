//! Kill command - terminate process on a port.

use anyhow::{bail, Result};
use portkiller_core::{PortScanner, ProcessKiller};

pub async fn run(port: u16, force: bool) -> Result<()> {
    let scanner = PortScanner::new();
    let ports = scanner.scan().await?;

    // Find the port
    let port_info = ports.iter().find(|p| p.port == port);

    let port_info = match port_info {
        Some(p) => p,
        None => {
            println!("No process found on port {}.", port);
            return Ok(());
        }
    };

    let pid = port_info.pid;
    let process_name = &port_info.process_name;

    println!(
        "Killing {} (PID: {}) on port {}{}...",
        process_name,
        pid,
        port,
        if force { " [FORCE]" } else { "" }
    );

    let killer = ProcessKiller::new();

    let result = if force {
        killer.kill(pid, true).await
    } else {
        killer.kill_gracefully(pid).await
    };

    match result {
        Ok(true) => {
            println!("✓ Process killed successfully.");
            Ok(())
        }
        Ok(false) => {
            println!("Process already terminated.");
            Ok(())
        }
        Err(e) => {
            bail!("Failed to kill process: {}", e);
        }
    }
}
