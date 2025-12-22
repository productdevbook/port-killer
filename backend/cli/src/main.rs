//! PortKiller CLI - Manage processes on network ports
//!
//! A command-line tool for scanning ports, killing processes,
//! and managing favorites/watched ports.

mod commands;
mod tui;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "portkiller")]
#[command(author, version, about = "Manage processes on network ports")]
#[command(propagate_version = true)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Output in JSON format
    #[arg(long, global = true)]
    json: bool,

    /// Disable interactive TUI mode
    #[arg(long, global = true)]
    no_tui: bool,
}

#[derive(Subcommand)]
enum Commands {
    /// List all listening ports
    #[command(alias = "ls")]
    List {
        /// Filter by port number
        #[arg(short, long)]
        port: Option<u16>,

        /// Filter by process name
        #[arg(short = 'n', long)]
        name: Option<String>,
    },

    /// Kill process on a port
    Kill {
        /// Port number to kill
        port: u16,

        /// Force kill (SIGKILL) without graceful shutdown
        #[arg(short, long)]
        force: bool,
    },

    /// Manage favorite ports
    #[command(alias = "fav")]
    Favorites {
        #[command(subcommand)]
        action: FavoritesAction,
    },

    /// Manage watched ports
    Watch {
        #[command(subcommand)]
        action: WatchAction,
    },

    /// Show current configuration
    Config,
}

#[derive(Subcommand)]
enum FavoritesAction {
    /// Add a port to favorites
    Add { port: u16 },
    /// Remove a port from favorites
    #[command(alias = "rm")]
    Remove { port: u16 },
    /// List all favorite ports
    #[command(alias = "ls")]
    List,
}

#[derive(Subcommand)]
enum WatchAction {
    /// Add a port to watch list
    Add {
        port: u16,
        /// Notify on port start
        #[arg(long, default_value = "true")]
        on_start: bool,
        /// Notify on port stop
        #[arg(long, default_value = "true")]
        on_stop: bool,
    },
    /// Remove a port from watch list
    #[command(alias = "rm")]
    Remove { port: u16 },
    /// List all watched ports
    #[command(alias = "ls")]
    List,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Some(Commands::List { port, name }) => {
            commands::list::run(port, name, cli.json).await?;
        }
        Some(Commands::Kill { port, force }) => {
            commands::kill::run(port, force).await?;
        }
        Some(Commands::Favorites { action }) => match action {
            FavoritesAction::Add { port } => commands::favorites::add(port).await?,
            FavoritesAction::Remove { port } => commands::favorites::remove(port).await?,
            FavoritesAction::List => commands::favorites::list(cli.json).await?,
        },
        Some(Commands::Watch { action }) => match action {
            WatchAction::Add {
                port,
                on_start,
                on_stop,
            } => commands::watch::add(port, on_start, on_stop).await?,
            WatchAction::Remove { port } => commands::watch::remove(port).await?,
            WatchAction::List => commands::watch::list(cli.json).await?,
        },
        Some(Commands::Config) => {
            commands::config::show(cli.json).await?;
        }
        None => {
            // Default: Launch TUI or list ports
            if cli.no_tui || !atty::is(atty::Stream::Stdout) {
                commands::list::run(None, None, cli.json).await?;
            } else {
                tui::run().await?;
            }
        }
    }

    Ok(())
}
