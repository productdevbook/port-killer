//! List command - show all listening ports.

use anyhow::Result;
use portkiller_core::{PortScanner, ProcessType};

pub async fn run(port_filter: Option<u16>, name_filter: Option<String>, json: bool) -> Result<()> {
    let scanner = PortScanner::new();
    let mut ports = scanner.scan().await?;

    // Apply filters
    if let Some(p) = port_filter {
        ports.retain(|port| port.port == p);
    }
    if let Some(ref name) = name_filter {
        let name_lower = name.to_lowercase();
        ports.retain(|port| port.process_name.to_lowercase().contains(&name_lower));
    }

    if json {
        println!("{}", serde_json::to_string_pretty(&ports)?);
        return Ok(());
    }

    if ports.is_empty() {
        println!("No listening ports found.");
        return Ok(());
    }

    // Table header
    println!(
        "{:<6} {:<8} {:<20} {:<15} {:<8} COMMAND",
        "PORT", "PID", "PROCESS", "ADDRESS", "TYPE"
    );
    println!("{}", "-".repeat(80));

    for port in &ports {
        let type_str = match port.process_type() {
            ProcessType::WebServer => "Web",
            ProcessType::Database => "DB",
            ProcessType::Development => "Dev",
            ProcessType::System => "Sys",
            ProcessType::Other => "-",
        };

        let command = truncate(&port.command, 30);
        let process_name = truncate(&port.process_name, 20);
        let address = truncate(&port.address, 15);

        println!(
            "{:<6} {:<8} {:<20} {:<15} {:<8} {}",
            port.port, port.pid, process_name, address, type_str, command
        );
    }

    println!("\nTotal: {} ports", ports.len());
    Ok(())
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max - 1])
    }
}
