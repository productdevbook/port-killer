package tui

import (
	"fmt"

	"github.com/charmbracelet/bubbles/key"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// Update handles all messages
func (a *App) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		a.width = msg.Width
		a.height = msg.Height
		a.recalcColumns()
		// Update log viewer dimensions if active
		if a.logViewer != nil {
			a.logViewer.width = a.width / 2
			a.logViewer.height = a.height - 6
		}
		return a, nil

	case configLoadedMsg:
		a.config = msg.config
		a.updateFilteredPorts()
		return a, nil

	case portsLoadedMsg:
		a.loading = false
		if msg.err != nil {
			a.setStatus(fmt.Sprintf("Error: %v", msg.err), true)
		} else {
			a.updatePorts(msg.ports)
		}
		return a, nil

	case portKilledMsg:
		if msg.err != nil {
			a.setStatus(fmt.Sprintf("Failed to kill port %d: %v", msg.port, msg.err), true)
		} else {
			a.setStatus(fmt.Sprintf("Killed process on port %d", msg.port), false)
		}
		return a, a.loadPorts()

	case tickMsg:
		if a.autoRefresh && !a.searching && a.viewMode == ViewList {
			return a, tea.Batch(a.loadPorts(), tickCmd(a.refreshInterval))
		}
		return a, tickCmd(a.refreshInterval)

	case spinner.TickMsg:
		var cmd tea.Cmd
		a.spinner, cmd = a.spinner.Update(msg)
		return a, cmd

	case commandExecutedMsg:
		return a.handleCommandExecuted(msg)

	case logViewerOpenMsg:
		return a.openLogViewer(msg.port)

	case logViewerCloseMsg:
		a.logViewerActive = false
		a.viewMode = ViewList
		return a, nil

	case logEntriesLoadedMsg:
		if msg.err == nil && a.logViewer != nil {
			a.logViewer.entries = msg.entries
		}
		return a, nil

	case clipboardCopiedMsg:
		if msg.err != nil {
			a.setStatus("Failed to copy to clipboard", true)
		} else {
			a.setStatus("Copied to clipboard", false)
		}
		a.viewMode = ViewList
		a.exportActive = false
		return a, nil

	case statusMsg:
		a.setStatus(msg.text, msg.isError)
		return a, nil

	case tea.KeyMsg:
		return a.handleKeyMsg(msg)
	}

	return a, tea.Batch(cmds...)
}

// handleKeyMsg routes key messages based on current view mode
func (a *App) handleKeyMsg(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	// Global quit
	if key.Matches(msg, a.keys.Quit) && a.viewMode == ViewList && !a.searching {
		return a, tea.Quit
	}

	// Handle based on view mode
	switch a.viewMode {
	case ViewCommandPalette:
		return a.handleCommandPaletteKeys(msg)
	case ViewLogViewer:
		return a.handleLogViewerKeys(msg)
	case ViewExportDialog:
		return a.handleExportDialogKeys(msg)
	case ViewHelp:
		return a.handleHelpKeys(msg)
	case ViewDetail:
		return a.handleDetailKeys(msg)
	case ViewConfirmKill:
		return a.handleConfirmKillKeys(msg)
	default:
		// Handle search input mode
		if a.searching {
			return a.handleSearchInput(msg)
		}
		return a.handleListKeys(msg)
	}
}

// handleListKeys handles keys in list view
func (a *App) handleListKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	// Navigation
	case key.Matches(msg, a.keys.Up):
		a.moveCursor(-1)
	case key.Matches(msg, a.keys.Down):
		a.moveCursor(1)
	case key.Matches(msg, a.keys.PageUp):
		a.moveCursor(-10)
	case key.Matches(msg, a.keys.PageDown):
		a.moveCursor(10)
	case key.Matches(msg, a.keys.Home):
		a.cursor = 0
	case key.Matches(msg, a.keys.End):
		if len(a.filtered) > 0 {
			a.cursor = len(a.filtered) - 1
		}

	// Command palette (/ key)
	case key.Matches(msg, a.keys.Search):
		a.viewMode = ViewCommandPalette
		a.paletteInput.SetValue("")
		a.paletteFiltered = GetBuiltinCommands()
		a.paletteCursor = 0
		a.paletteInput.Focus()
		return a, textinput.Blink

	// Selection
	case msg.String() == " ":
		a.ToggleSelection(a.cursor)

	case msg.String() == "ctrl+a":
		a.SelectAll()

	// Quick actions
	case key.Matches(msg, a.keys.Help):
		a.viewMode = ViewHelp

	case key.Matches(msg, a.keys.Detail):
		if len(a.filtered) > 0 {
			a.viewMode = ViewDetail
		}

	case key.Matches(msg, a.keys.Kill):
		return a.killSelected(false)

	case key.Matches(msg, a.keys.ForceKill):
		return a.killSelected(true)

	case key.Matches(msg, a.keys.Favorite):
		return a.toggleFavorite()

	case key.Matches(msg, a.keys.Watch):
		return a.toggleWatch()

	case key.Matches(msg, a.keys.Refresh):
		a.loading = true
		return a, tea.Batch(a.loadPorts(), a.spinner.Tick)

	case key.Matches(msg, a.keys.GroupByType):
		a.groupByType = !a.groupByType
		a.updateFilteredPorts()

	case key.Matches(msg, a.keys.SortByPort):
		a.sortMode = SortByPort
		a.updateFilteredPorts()

	case key.Matches(msg, a.keys.SortByName):
		a.sortMode = SortByName
		a.updateFilteredPorts()

	// Copy shortcut
	case msg.String() == "c":
		a.viewMode = ViewExportDialog
		a.exportActive = true
		a.exportCursor = 0

	// Logs shortcut
	case msg.String() == "L":
		if len(a.filtered) > 0 && a.cursor < len(a.filtered) {
			return a.openLogViewer(a.filtered[a.cursor])
		}
	}

	return a, nil
}

// handleCommandPaletteKeys handles keys in command palette view
func (a *App) handleCommandPaletteKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, a.keys.Escape):
		a.viewMode = ViewList
		a.paletteInput.SetValue("")
		return a, nil

	case key.Matches(msg, a.keys.Up):
		if a.paletteCursor > 0 {
			a.paletteCursor--
		}
		return a, nil

	case key.Matches(msg, a.keys.Down):
		if a.paletteCursor < len(a.paletteFiltered)-1 {
			a.paletteCursor++
		}
		return a, nil

	case key.Matches(msg, a.keys.Enter):
		// Execute selected command
		if len(a.paletteFiltered) > 0 && a.paletteCursor < len(a.paletteFiltered) {
			cmd := a.paletteFiltered[a.paletteCursor]
			a.viewMode = ViewList
			a.paletteInput.SetValue("")
			if cmd.Handler != nil {
				return a, cmd.Handler(a)
			}
		}
		a.viewMode = ViewList
		return a, nil
	}

	// Update input and filter commands
	var cmd tea.Cmd
	a.paletteInput, cmd = a.paletteInput.Update(msg)

	// Filter commands based on input
	query := a.paletteInput.Value()
	registry := NewCommandRegistry()
	a.paletteFiltered = registry.Filter(query)
	if a.paletteCursor >= len(a.paletteFiltered) {
		a.paletteCursor = 0
	}

	return a, cmd
}

// handleLogViewerKeys handles keys in log viewer
func (a *App) handleLogViewerKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, a.keys.Escape), msg.String() == "q":
		a.logViewerActive = false
		a.viewMode = ViewList
		return a, nil

	case key.Matches(msg, a.keys.Up), msg.String() == "k":
		if a.logViewer != nil && a.logViewer.scroll > 0 {
			a.logViewer.scroll--
			a.logViewer.follow = false
		}

	case key.Matches(msg, a.keys.Down), msg.String() == "j":
		if a.logViewer != nil {
			a.logViewer.scroll++
			// Check if at bottom
			if a.logViewer.scroll >= len(a.logViewer.entries)-a.logViewer.height {
				a.logViewer.follow = true
			}
		}

	case msg.String() == "f":
		// Toggle follow mode
		if a.logViewer != nil {
			a.logViewer.follow = !a.logViewer.follow
			if a.logViewer.follow {
				a.logViewer.scroll = len(a.logViewer.entries) - a.logViewer.height
				if a.logViewer.scroll < 0 {
					a.logViewer.scroll = 0
				}
			}
		}

	case msg.String() == "1":
		// Filter: show all
		if a.logViewer != nil {
			a.logViewer.filter = -1
		}

	case msg.String() == "2":
		// Filter: network only
		if a.logViewer != nil {
			a.logViewer.filter = LogSourceNetwork
		}

	case msg.String() == "3":
		// Filter: stdout only
		if a.logViewer != nil {
			a.logViewer.filter = LogSourceStdout
		}

	case msg.String() == "4":
		// Filter: stderr only
		if a.logViewer != nil {
			a.logViewer.filter = LogSourceStderr
		}

	case msg.String() == "c":
		// Copy logs
		if a.logViewer != nil && len(a.logViewer.entries) > 0 {
			return a, a.copyLogsToClipboard()
		}
	}

	return a, nil
}

// handleExportDialogKeys handles keys in export dialog
func (a *App) handleExportDialogKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, a.keys.Escape):
		a.viewMode = ViewList
		a.exportActive = false
		return a, nil

	case key.Matches(msg, a.keys.Up):
		if a.exportCursor > 0 {
			a.exportCursor--
		}

	case key.Matches(msg, a.keys.Down):
		if a.exportCursor < len(a.exportFormats)-1 {
			a.exportCursor++
		}

	case key.Matches(msg, a.keys.Enter):
		// Execute export with selected format
		format := a.exportFormats[a.exportCursor]
		return a, a.exportToClipboard(format)
	}

	return a, nil
}

// handleHelpKeys handles keys in help view
func (a *App) handleHelpKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if key.Matches(msg, a.keys.Escape, a.keys.Help, a.keys.Quit) {
		a.viewMode = ViewList
	}
	return a, nil
}

// handleDetailKeys handles keys in detail view
func (a *App) handleDetailKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, a.keys.Escape):
		a.viewMode = ViewList
	case key.Matches(msg, a.keys.Kill):
		return a.killSelected(false)
	case key.Matches(msg, a.keys.ForceKill):
		return a.killSelected(true)
	case msg.String() == "c":
		a.viewMode = ViewExportDialog
		a.exportActive = true
		a.exportCursor = 0
	case msg.String() == "L":
		if len(a.filtered) > 0 && a.cursor < len(a.filtered) {
			return a.openLogViewer(a.filtered[a.cursor])
		}
	}
	return a, nil
}

// handleConfirmKillKeys handles keys in kill confirmation view
func (a *App) handleConfirmKillKeys(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "y", "Y", "enter":
		if a.pendingKill != nil {
			item := a.pendingKill
			a.pendingKill = nil
			a.viewMode = ViewList
			return a, func() tea.Msg {
				err := a.scanner.Kill(item.Port.PID, a.pendingForceKill)
				return portKilledMsg{port: item.Port.Port, err: err}
			}
		}
		a.viewMode = ViewList
		return a, nil

	case "n", "N", "esc", "q":
		a.pendingKill = nil
		a.viewMode = ViewList
		return a, nil
	}

	return a, nil
}

// handleSearchInput handles input when in search mode
func (a *App) handleSearchInput(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch {
	case key.Matches(msg, a.keys.Escape):
		a.searching = false
		a.searchInput.SetValue("")
		a.updateFilteredPorts()
		return a, nil

	case key.Matches(msg, a.keys.Enter):
		a.searching = false
		return a, nil
	}

	var cmd tea.Cmd
	a.searchInput, cmd = a.searchInput.Update(msg)
	a.filterPorts(a.searchInput.Value())
	return a, cmd
}

// handleCommandExecuted handles command execution results
func (a *App) handleCommandExecuted(msg commandExecutedMsg) (tea.Model, tea.Cmd) {
	switch msg.id {
	case "favorite":
		return a.toggleFavorite()
	case "watch":
		return a.toggleWatch()
	}
	return a, nil
}

// openLogViewer opens the log viewer for a port
func (a *App) openLogViewer(port PortItem) (tea.Model, tea.Cmd) {
	a.logViewerPort = &port
	a.logViewerActive = true
	a.viewMode = ViewLogViewer

	if a.logViewer == nil {
		a.logViewer = &LogViewer{
			follow: true,
			filter: -1,
		}
	}
	a.logViewer.port = &port
	a.logViewer.entries = nil
	a.logViewer.scroll = 0
	a.logViewer.visible = true
	a.logViewer.width = a.width / 2
	a.logViewer.height = a.height - 6

	// Load log entries
	return a, a.loadLogEntries(port)
}

// loadLogEntries loads log entries for a port
func (a *App) loadLogEntries(port PortItem) tea.Cmd {
	return func() tea.Msg {
		entries := FetchNetworkInfo(port.Port.Port, port.Port.PID)
		return logEntriesLoadedMsg{entries: entries}
	}
}

// copyLogsToClipboard copies log entries to clipboard
func (a *App) copyLogsToClipboard() tea.Cmd {
	if a.logViewer == nil || len(a.logViewer.entries) == 0 {
		return nil
	}

	var content string
	for _, entry := range a.logViewer.entries {
		content += fmt.Sprintf("[%s] %s %s\n",
			entry.Time.Format("15:04:05"),
			entry.Source.String(),
			entry.Content)
	}

	return CopyToClipboard(content)
}
