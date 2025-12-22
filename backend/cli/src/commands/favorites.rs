//! Favorites command - manage favorite ports.

use anyhow::Result;
use portkiller_core::ConfigStore;

pub async fn add(port: u16) -> Result<()> {
    let store = ConfigStore::new()?;
    store.add_favorite(port).await?;
    println!("✓ Added port {} to favorites.", port);
    Ok(())
}

pub async fn remove(port: u16) -> Result<()> {
    let store = ConfigStore::new()?;
    store.remove_favorite(port).await?;
    println!("✓ Removed port {} from favorites.", port);
    Ok(())
}

pub async fn list(json: bool) -> Result<()> {
    let store = ConfigStore::new()?;
    let favorites = store.get_favorites().await?;

    if json {
        let sorted: Vec<u16> = {
            let mut v: Vec<_> = favorites.into_iter().collect();
            v.sort();
            v
        };
        println!("{}", serde_json::to_string_pretty(&sorted)?);
        return Ok(());
    }

    if favorites.is_empty() {
        println!("No favorite ports.");
        return Ok(());
    }

    println!("Favorite ports:");
    let mut sorted: Vec<_> = favorites.into_iter().collect();
    sorted.sort();
    for port in sorted {
        println!("  {}", port);
    }

    Ok(())
}
