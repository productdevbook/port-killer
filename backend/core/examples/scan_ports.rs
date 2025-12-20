//! Example: Scan and display all listening ports.

use portkiller_core::{PortScanner, ProcessType};

#[tokio::main(flavor = "current_thread")]
async fn main() {
    println!("Scanning ports...\n");

    let scanner = PortScanner::new();

    match scanner.scan().await {
        Ok(ports) => {
            if ports.is_empty() {
                println!("No listening ports found.");
                return;
            }

            println!(
                "{:<6} {:<8} {:<20} {:<15} {:<10} {}",
                "PORT", "PID", "PROCESS", "ADDRESS", "TYPE", "COMMAND"
            );
            println!("{}", "-".repeat(100));

            for port in &ports {
                let type_str = match port.process_type() {
                    ProcessType::WebServer => "Web",
                    ProcessType::Database => "DB",
                    ProcessType::Development => "Dev",
                    ProcessType::System => "Sys",
                    ProcessType::Other => "Other",
                };

                let command = if port.command.len() > 40 {
                    format!("{}...", &port.command[..40])
                } else {
                    port.command.clone()
                };

                println!(
                    "{:<6} {:<8} {:<20} {:<15} {:<10} {}",
                    port.port,
                    port.pid,
                    &port.process_name[..port.process_name.len().min(20)],
                    &port.address[..port.address.len().min(15)],
                    type_str,
                    command
                );
            }

            println!("\nTotal: {} ports", ports.len());
        }
        Err(e) => {
            eprintln!("Error scanning ports: {}", e);
        }
    }
}
