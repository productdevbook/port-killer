//! TUI rendering.

use portkiller_core::ProcessType;
use ratatui::{
    prelude::*,
    widgets::{Block, Borders, Cell, Paragraph, Row, Table, TableState},
};

use super::app::App;

pub fn draw(f: &mut Frame, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Header
            Constraint::Min(0),    // Table
            Constraint::Length(3), // Footer
        ])
        .split(f.area());

    draw_header(f, app, chunks[0]);
    draw_table(f, app, chunks[1]);
    draw_footer(f, app, chunks[2]);
}

fn draw_header(f: &mut Frame, app: &App, area: Rect) {
    let title = if app.is_searching() {
        format!("PortKiller | Search: {}_", app.search_query)
    } else {
        format!("PortKiller | {} ports", app.filtered_ports().len())
    };

    let header = Paragraph::new(title)
        .style(Style::default().fg(Color::Cyan).bold())
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );

    f.render_widget(header, area);
}

fn draw_table(f: &mut Frame, app: &App, area: Rect) {
    let header_cells = ["PORT", "PID", "PROCESS", "ADDRESS", "TYPE", "★", "👁"]
        .iter()
        .map(|h| Cell::from(*h).style(Style::default().fg(Color::Yellow).bold()));
    let header = Row::new(header_cells).height(1).bottom_margin(1);

    let filtered = app.filtered_ports();
    let rows = filtered.iter().enumerate().map(|(i, port)| {
        let is_selected = i == app.selected;
        let is_favorite = app.favorites.contains(&port.port);
        let is_watched = app.watched.contains(&port.port);

        let type_str = match port.process_type() {
            ProcessType::WebServer => "Web",
            ProcessType::Database => "DB",
            ProcessType::Development => "Dev",
            ProcessType::System => "Sys",
            ProcessType::Other => "-",
        };

        let type_color = match port.process_type() {
            ProcessType::WebServer => Color::Green,
            ProcessType::Database => Color::Blue,
            ProcessType::Development => Color::Yellow,
            ProcessType::System => Color::Magenta,
            ProcessType::Other => Color::DarkGray,
        };

        let cells = vec![
            Cell::from(port.port.to_string()),
            Cell::from(port.pid.to_string()),
            Cell::from(truncate(&port.process_name, 20)),
            Cell::from(truncate(&port.address, 15)),
            Cell::from(type_str).style(Style::default().fg(type_color)),
            Cell::from(if is_favorite { "★" } else { " " })
                .style(Style::default().fg(Color::Yellow)),
            Cell::from(if is_watched { "👁" } else { " " }).style(Style::default().fg(Color::Cyan)),
        ];

        let style = if is_selected {
            Style::default().bg(Color::DarkGray).fg(Color::White)
        } else {
            Style::default()
        };

        Row::new(cells).style(style)
    });

    let widths = [
        Constraint::Length(6),
        Constraint::Length(8),
        Constraint::Length(20),
        Constraint::Length(15),
        Constraint::Length(5),
        Constraint::Length(2),
        Constraint::Length(2),
    ];

    let table = Table::new(rows, widths)
        .header(header)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray))
                .title(" Listening Ports "),
        )
        .row_highlight_style(Style::default().add_modifier(Modifier::BOLD));

    let mut state = TableState::default();
    state.select(Some(app.selected));

    f.render_stateful_widget(table, area, &mut state);
}

fn draw_footer(f: &mut Frame, app: &App, area: Rect) {
    let status = app.get_status().unwrap_or("");

    let help = if app.is_searching() {
        "Type to search | Enter: done | Esc: cancel"
    } else {
        "j/k: navigate | x: kill | f: favorite | w: watch | /: search | r: refresh | q: quit"
    };

    let footer_text = if status.is_empty() {
        help.to_string()
    } else {
        format!("{} | {}", status, help)
    };

    let footer = Paragraph::new(footer_text)
        .style(Style::default().fg(Color::DarkGray))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::DarkGray)),
        );

    f.render_widget(footer, area);
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max - 1])
    }
}
