//! TUI application state.

use std::collections::HashSet;
use std::time::{Duration, Instant};

use anyhow::Result;
use portkiller_core::{ConfigStore, PortInfo, PortScanner, ProcessKiller};

pub struct App {
    pub ports: Vec<PortInfo>,
    pub favorites: HashSet<u16>,
    pub watched: HashSet<u16>,
    pub selected: usize,
    pub search_query: String,
    pub searching: bool,
    pub status_message: Option<(String, Instant)>,
    last_refresh: Instant,
    scanner: PortScanner,
    killer: ProcessKiller,
    config: ConfigStore,
}

impl App {
    pub async fn new() -> Result<Self> {
        let scanner = PortScanner::new();
        let config = ConfigStore::new()?;
        let killer = ProcessKiller::new();

        let ports = scanner.scan().await?;
        let favorites = config.get_favorites().await?;
        let watched_list = config.get_watched_ports().await?;
        let watched: HashSet<u16> = watched_list.iter().map(|w| w.port).collect();

        Ok(Self {
            ports,
            favorites,
            watched,
            selected: 0,
            search_query: String::new(),
            searching: false,
            status_message: None,
            last_refresh: Instant::now(),
            scanner,
            killer,
            config,
        })
    }

    pub fn filtered_ports(&self) -> Vec<&PortInfo> {
        if self.search_query.is_empty() {
            self.ports.iter().collect()
        } else {
            let query = self.search_query.to_lowercase();
            self.ports
                .iter()
                .filter(|p| {
                    p.process_name.to_lowercase().contains(&query)
                        || p.port.to_string().contains(&query)
                        || p.command.to_lowercase().contains(&query)
                })
                .collect()
        }
    }

    pub fn selected_port(&self) -> Option<&PortInfo> {
        let filtered = self.filtered_ports();
        filtered.get(self.selected).copied()
    }

    pub fn next(&mut self) {
        let len = self.filtered_ports().len();
        if len > 0 {
            self.selected = (self.selected + 1) % len;
        }
    }

    pub fn previous(&mut self) {
        let len = self.filtered_ports().len();
        if len > 0 {
            self.selected = self.selected.checked_sub(1).unwrap_or(len - 1);
        }
    }

    pub fn first(&mut self) {
        self.selected = 0;
    }

    pub fn last(&mut self) {
        let len = self.filtered_ports().len();
        if len > 0 {
            self.selected = len - 1;
        }
    }

    pub async fn refresh(&mut self) -> Result<()> {
        self.ports = self.scanner.scan().await?;
        self.favorites = self.config.get_favorites().await?;
        let watched_list = self.config.get_watched_ports().await?;
        self.watched = watched_list.iter().map(|w| w.port).collect();
        self.last_refresh = Instant::now();

        // Ensure selected is within bounds
        let len = self.filtered_ports().len();
        if self.selected >= len && len > 0 {
            self.selected = len - 1;
        }

        self.set_status("Refreshed");
        Ok(())
    }

    pub fn should_refresh(&self) -> bool {
        self.last_refresh.elapsed() > Duration::from_secs(5)
    }

    pub async fn kill_selected(&mut self) -> Result<()> {
        if let Some(port) = self.selected_port() {
            let pid = port.pid;
            let port_num = port.port;
            let name = port.process_name.clone();

            match self.killer.kill_gracefully(pid).await {
                Ok(true) => {
                    self.set_status(&format!("Killed {} on port {}", name, port_num));
                    self.refresh().await?;
                }
                Ok(false) => {
                    self.set_status(&format!("Process {} already terminated", pid));
                }
                Err(e) => {
                    self.set_status(&format!("Failed to kill: {}", e));
                }
            }
        }
        Ok(())
    }

    pub async fn toggle_favorite(&mut self) -> Result<()> {
        if let Some(port) = self.selected_port() {
            let port_num = port.port;
            if self.favorites.contains(&port_num) {
                self.config.remove_favorite(port_num).await?;
                self.favorites.remove(&port_num);
                self.set_status(&format!("Removed {} from favorites", port_num));
            } else {
                self.config.add_favorite(port_num).await?;
                self.favorites.insert(port_num);
                self.set_status(&format!("Added {} to favorites", port_num));
            }
        }
        Ok(())
    }

    pub async fn toggle_watch(&mut self) -> Result<()> {
        if let Some(port) = self.selected_port() {
            let port_num = port.port;
            if self.watched.contains(&port_num) {
                self.config.remove_watched_port(port_num).await?;
                self.watched.remove(&port_num);
                self.set_status(&format!("Stopped watching {}", port_num));
            } else {
                self.config.add_watched_port(port_num).await?;
                self.watched.insert(port_num);
                self.set_status(&format!("Now watching {}", port_num));
            }
        }
        Ok(())
    }

    pub fn start_search(&mut self) {
        self.searching = true;
        self.search_query.clear();
    }

    pub fn end_search(&mut self) {
        self.searching = false;
    }

    pub fn is_searching(&self) -> bool {
        self.searching
    }

    pub fn search_input(&mut self, c: char) {
        self.search_query.push(c);
        self.selected = 0;
    }

    pub fn search_backspace(&mut self) {
        self.search_query.pop();
        self.selected = 0;
    }

    fn set_status(&mut self, msg: &str) {
        self.status_message = Some((msg.to_string(), Instant::now()));
    }

    pub fn get_status(&self) -> Option<&str> {
        self.status_message.as_ref().and_then(|(msg, time)| {
            if time.elapsed() < Duration::from_secs(3) {
                Some(msg.as_str())
            } else {
                None
            }
        })
    }
}
