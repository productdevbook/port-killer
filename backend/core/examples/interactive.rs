//! Interactive testing for portkiller-core.
//!
//! Usage:
//!   cargo run --example interactive scan          # Scan ports
//!   cargo run --example interactive kill <pid>    # Kill process (graceful)
//!   cargo run --example interactive kill -f <pid> # Kill process (force)
//!   cargo run --example interactive config        # Show config
//!   cargo run --example interactive fav add 3000  # Add favorite
//!   cargo run --example interactive fav rm 3000   # Remove favorite
//!   cargo run --example interactive watch 5432    # Watch a port

use portkiller_core::{ConfigStore, PortScanner, ProcessKiller, ProcessType};
use std::env;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_help();
        return;
    }

    match args[1].as_str() {
        "scan" => scan_ports().await,
        "kill" => {
            if args.len() < 3 {
                eprintln!("Usage: interactive kill [-f] <pid>");
                return;
            }
            let (force, pid_str) = if args[2] == "-f" {
                if args.len() < 4 {
                    eprintln!("Usage: interactive kill -f <pid>");
                    return;
                }
                (true, &args[3])
            } else {
                (false, &args[2])
            };
            if let Ok(pid) = pid_str.parse() {
                kill_process(pid, force).await;
            } else {
                eprintln!("Invalid PID: {}", pid_str);
            }
        }
        "config" => show_config().await,
        "fav" => {
            if args.len() < 4 {
                eprintln!("Usage: interactive fav <add|rm|list> [port]");
                return;
            }
            match args[2].as_str() {
                "add" => {
                    if let Ok(port) = args[3].parse() {
                        add_favorite(port).await;
                    }
                }
                "rm" => {
                    if let Ok(port) = args[3].parse() {
                        remove_favorite(port).await;
                    }
                }
                "list" => list_favorites().await,
                _ => eprintln!("Unknown fav command: {}", args[2]),
            }
        }
        "watch" => {
            if args.len() < 3 {
                eprintln!("Usage: interactive watch <port>");
                return;
            }
            if let Ok(port) = args[2].parse() {
                watch_port(port).await;
            }
        }
        "help" | "-h" | "--help" => print_help(),
        _ => {
            eprintln!("Unknown command: {}", args[1]);
            print_help();
        }
    }
}

fn print_help() {
    println!(
        r#"PortKiller Core - Interactive Testing

USAGE:
    cargo run --example interactive <command> [args]

COMMANDS:
    scan              Scan and list all listening ports
    kill [-f] <pid>   Kill a process (-f for force/SIGKILL)
    config            Show current configuration
    fav add <port>    Add port to favorites
    fav rm <port>     Remove port from favorites
    fav list          List all favorites
    watch <port>      Add port to watch list
    help              Show this help message

EXAMPLES:
    cargo run --example interactive scan
    cargo run --example interactive kill 1234
    cargo run --example interactive kill -f 1234
    cargo run --example interactive fav add 3000
    cargo run --example interactive fav list
"#
    );
}

async fn scan_ports() {
    println!("Scanning ports...\n");
    let scanner = PortScanner::new();

    match scanner.scan().await {
        Ok(ports) => {
            if ports.is_empty() {
                println!("No listening ports found.");
                return;
            }

            println!(
                "{:<6} {:<8} {:<25} {:<15} {:<6}",
                "PORT", "PID", "PROCESS", "ADDRESS", "TYPE"
            );
            println!("{}", "-".repeat(70));

            for port in &ports {
                let type_str = match port.process_type() {
                    ProcessType::WebServer => "Web",
                    ProcessType::Database => "DB",
                    ProcessType::Development => "Dev",
                    ProcessType::System => "Sys",
                    ProcessType::Other => "-",
                };

                println!(
                    "{:<6} {:<8} {:<25} {:<15} {:<6}",
                    port.port,
                    port.pid,
                    truncate(&port.process_name, 25),
                    truncate(&port.address, 15),
                    type_str,
                );
            }

            println!("\nTotal: {} ports", ports.len());
        }
        Err(e) => eprintln!("Error: {}", e),
    }
}

async fn kill_process(pid: u32, force: bool) {
    let killer = ProcessKiller::new();

    println!(
        "Killing process {} ({})...",
        pid,
        if force { "SIGKILL" } else { "graceful" }
    );

    let result = if force {
        killer.kill(pid, true).await
    } else {
        killer.kill_gracefully(pid).await
    };

    match result {
        Ok(true) => println!("Process {} killed successfully.", pid),
        Ok(false) => println!("Process {} not found (already terminated?).", pid),
        Err(e) => eprintln!("Failed to kill process {}: {}", pid, e),
    }
}

async fn show_config() {
    let store = match ConfigStore::new() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Failed to create config store: {}", e);
            return;
        }
    };

    let favorites = store.get_favorites().await.unwrap_or_default();
    let watched = store.get_watched_ports().await.unwrap_or_default();

    println!("Configuration (~/.portkiller/config.json)\n");

    println!("Favorites: {:?}", favorites.iter().collect::<Vec<_>>());

    println!("\nWatched Ports:");
    if watched.is_empty() {
        println!("  (none)");
    } else {
        for wp in &watched {
            println!(
                "  Port {}: start={}, stop={}",
                wp.port, wp.notify_on_start, wp.notify_on_stop
            );
        }
    }
}

async fn add_favorite(port: u16) {
    let store = match ConfigStore::new() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Failed to create config store: {}", e);
            return;
        }
    };

    match store.add_favorite(port).await {
        Ok(()) => println!("Added port {} to favorites.", port),
        Err(e) => eprintln!("Failed to add favorite: {}", e),
    }
}

async fn remove_favorite(port: u16) {
    let store = match ConfigStore::new() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Failed to create config store: {}", e);
            return;
        }
    };

    match store.remove_favorite(port).await {
        Ok(()) => println!("Removed port {} from favorites.", port),
        Err(e) => eprintln!("Failed to remove favorite: {}", e),
    }
}

async fn list_favorites() {
    let store = match ConfigStore::new() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Failed to create config store: {}", e);
            return;
        }
    };

    match store.get_favorites().await {
        Ok(favorites) => {
            if favorites.is_empty() {
                println!("No favorites.");
            } else {
                println!("Favorites:");
                let mut sorted: Vec<_> = favorites.into_iter().collect();
                sorted.sort();
                for port in sorted {
                    println!("  {}", port);
                }
            }
        }
        Err(e) => eprintln!("Failed to get favorites: {}", e),
    }
}

async fn watch_port(port: u16) {
    let store = match ConfigStore::new() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Failed to create config store: {}", e);
            return;
        }
    };

    match store.add_watched_port(port).await {
        Ok(wp) => println!(
            "Now watching port {} (id: {}, start: {}, stop: {})",
            wp.port, wp.id, wp.notify_on_start, wp.notify_on_stop
        ),
        Err(e) => eprintln!("Failed to watch port: {}", e),
    }
}

fn truncate(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else {
        format!("{}...", &s[..max_len - 3])
    }
}
