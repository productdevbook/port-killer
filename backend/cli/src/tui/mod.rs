//! Terminal User Interface using ratatui.

mod app;
mod ui;

use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::prelude::*;
use std::io;

use app::App;

pub async fn run() -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app and run
    let mut app = App::new().await?;
    let result = run_app(&mut terminal, &mut app).await;

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    result
}

async fn run_app<B: Backend>(terminal: &mut Terminal<B>, app: &mut App) -> Result<()> {
    loop {
        terminal.draw(|f| ui::draw(f, app))?;

        if event::poll(std::time::Duration::from_millis(100))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                        KeyCode::Char('r') => app.refresh().await?,
                        KeyCode::Char('j') | KeyCode::Down => app.next(),
                        KeyCode::Char('k') | KeyCode::Up => app.previous(),
                        KeyCode::Char('g') => app.first(),
                        KeyCode::Char('G') => app.last(),
                        KeyCode::Char('x') | KeyCode::Delete => app.kill_selected().await?,
                        KeyCode::Char('f') => app.toggle_favorite().await?,
                        KeyCode::Char('w') => app.toggle_watch().await?,
                        KeyCode::Char('/') => app.start_search(),
                        KeyCode::Enter => {
                            if app.is_searching() {
                                app.end_search();
                            }
                        }
                        KeyCode::Char(c) if app.is_searching() => app.search_input(c),
                        KeyCode::Backspace if app.is_searching() => app.search_backspace(),
                        _ => {}
                    }
                }
            }
        }

        // Auto-refresh every 5 seconds
        if app.should_refresh() {
            app.refresh().await?;
        }
    }
}
