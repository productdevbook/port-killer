//! Config command - show current configuration.

use anyhow::Result;
use portkiller_core::ConfigStore;
use serde::Serialize;

#[derive(Serialize)]
struct ConfigOutput {
    favorites: Vec<u16>,
    watched_ports: Vec<WatchedPortOutput>,
}

#[derive(Serialize)]
struct WatchedPortOutput {
    port: u16,
    notify_on_start: bool,
    notify_on_stop: bool,
}

pub async fn show(json: bool) -> Result<()> {
    let store = ConfigStore::new()?;
    let favorites = store.get_favorites().await?;
    let watched = store.get_watched_ports().await?;

    if json {
        let output = ConfigOutput {
            favorites: {
                let mut v: Vec<_> = favorites.into_iter().collect();
                v.sort();
                v
            },
            watched_ports: watched
                .into_iter()
                .map(|w| WatchedPortOutput {
                    port: w.port,
                    notify_on_start: w.notify_on_start,
                    notify_on_stop: w.notify_on_stop,
                })
                .collect(),
        };
        println!("{}", serde_json::to_string_pretty(&output)?);
        return Ok(());
    }

    println!("Configuration (~/.portkiller/config.json)\n");

    // Favorites
    println!("Favorites:");
    if favorites.is_empty() {
        println!("  (none)");
    } else {
        let mut sorted: Vec<_> = favorites.into_iter().collect();
        sorted.sort();
        for port in sorted {
            println!("  {}", port);
        }
    }

    // Watched
    println!("\nWatched Ports:");
    if watched.is_empty() {
        println!("  (none)");
    } else {
        for wp in watched {
            println!(
                "  {} (start: {}, stop: {})",
                wp.port,
                if wp.notify_on_start { "✓" } else { "✗" },
                if wp.notify_on_stop { "✓" } else { "✗" }
            );
        }
    }

    Ok(())
}
