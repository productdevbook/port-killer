//! Watch command - manage watched ports.

use anyhow::Result;
use portkiller_core::ConfigStore;

pub async fn add(port: u16, on_start: bool, on_stop: bool) -> Result<()> {
    let store = ConfigStore::new()?;

    // Check if already watching
    let watched = store.get_watched_ports().await?;
    if watched.iter().any(|w| w.port == port) {
        println!("Port {} is already being watched.", port);
        return Ok(());
    }

    let wp = store.add_watched_port(port).await?;

    // Update notification settings if different from defaults
    if !on_start || !on_stop {
        store.update_watched_port(port, on_start, on_stop).await?;
    }

    println!(
        "✓ Now watching port {} (notify: start={}, stop={})",
        wp.port, on_start, on_stop
    );
    Ok(())
}

pub async fn remove(port: u16) -> Result<()> {
    let store = ConfigStore::new()?;
    store.remove_watched_port(port).await?;
    println!("✓ Stopped watching port {}.", port);
    Ok(())
}

pub async fn list(json: bool) -> Result<()> {
    let store = ConfigStore::new()?;
    let watched = store.get_watched_ports().await?;

    if json {
        println!("{}", serde_json::to_string_pretty(&watched)?);
        return Ok(());
    }

    if watched.is_empty() {
        println!("No watched ports.");
        return Ok(());
    }

    println!("Watched ports:");
    println!("{:<8} {:<12} {:<12}", "PORT", "ON START", "ON STOP");
    println!("{}", "-".repeat(34));

    for wp in watched {
        println!(
            "{:<8} {:<12} {:<12}",
            wp.port,
            if wp.notify_on_start { "✓" } else { "-" },
            if wp.notify_on_stop { "✓" } else { "-" }
        );
    }

    Ok(())
}
