package tui

import (
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/productdevbook/port-killer/cli/internal/config"
	"github.com/productdevbook/port-killer/cli/internal/scanner"
)

// App represents the TUI application state
type App struct {
	// Data
	ports       []PortItem
	filtered    []PortItem
	config      *config.Config
	configStore config.Store
	scanner     scanner.Scanner

	// UI state
	cursor      int
	viewMode    ViewMode
	sortMode    SortMode
	groupByType bool
	width       int
	height      int

	// Column cache (recalculated on width change)
	cols      ColumnWidths
	colsWidth int

	// Core components
	searchInput textinput.Model
	spinner     spinner.Model
	keys        KeyMap

	// Command palette
	palette         *CommandPalette
	paletteInput    textinput.Model
	paletteFiltered []Command
	paletteCursor   int

	// Selection
	selection map[int]bool

	// Log viewer
	logViewer       *LogViewer
	logViewerPort   *PortItem
	logViewerActive bool

	// Export dialog
	exportFormats []ExportFormat
	exportCursor  int
	exportActive  bool

	// State flags
	searching    bool
	loading      bool
	statusText   string
	statusError  bool
	statusExpiry time.Time

	// Kill confirmation
	pendingKill      *PortItem
	pendingForceKill bool

	// Auto refresh
	autoRefresh     bool
	refreshInterval time.Duration
}

// CommandPalette holds command palette state
type CommandPalette struct {
	commands []Command
	filtered []Command
	cursor   int
	input    textinput.Model
	visible  bool
	width    int
	height   int
}

// LogViewer holds log viewer state
type LogViewer struct {
	port    *PortItem
	entries []LogEntry
	scroll  int
	follow  bool
	filter  LogSource
	width   int
	height  int
	visible bool
}

// New creates a new TUI application
func New() *App {
	// Search input
	ti := textinput.New()
	ti.Placeholder = "Search ports..."
	ti.CharLimit = 64
	ti.Width = 30

	// Palette input
	pi := textinput.New()
	pi.Placeholder = "Type a command..."
	pi.CharLimit = 64
	pi.Width = 40

	// Spinner
	s := spinner.New()
	s.Spinner = spinner.Dot

	// Create command palette
	palette := &CommandPalette{
		commands: GetBuiltinCommands(),
		input:    pi,
	}
	palette.filtered = palette.commands

	// Create log viewer
	logViewer := &LogViewer{
		follow: true,
		filter: -1, // Show all sources
	}

	return &App{
		keys:            DefaultKeyMap(),
		searchInput:     ti,
		spinner:         s,
		viewMode:        ViewList,
		sortMode:        SortByFavorites,
		autoRefresh:     true,
		refreshInterval: 5 * time.Second,
		scanner:         scanner.New(),
		configStore:     config.NewStore(),
		palette:         palette,
		paletteInput:    pi,
		selection:       make(map[int]bool),
		logViewer:       logViewer,
		exportFormats:   AllExportFormats(),
	}
}

// Init initializes the application
func (a *App) Init() tea.Cmd {
	return tea.Batch(
		a.loadPorts(),
		a.loadConfig(),
		tickCmd(a.refreshInterval),
	)
}

// loadPorts returns a command to load ports
func (a *App) loadPorts() tea.Cmd {
	return func() tea.Msg {
		ports, err := a.scanner.Scan()
		return portsLoadedMsg{ports: ports, err: err}
	}
}

// loadConfig loads the configuration
func (a *App) loadConfig() tea.Cmd {
	return func() tea.Msg {
		cfg, _ := a.configStore.Load()
		if cfg == nil {
			cfg = &config.Config{}
		}
		return configLoadedMsg{config: cfg}
	}
}

// tickCmd returns a tick command for auto-refresh
func tickCmd(d time.Duration) tea.Cmd {
	return tea.Tick(d, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

// Run starts the TUI application
func Run() error {
	p := tea.NewProgram(
		New(),
		tea.WithAltScreen(),
		tea.WithMouseCellMotion(),
	)

	_, err := p.Run()
	return err
}

// recalcColumns recalculates column widths if needed
func (a *App) recalcColumns() {
	if a.colsWidth == a.width {
		return
	}

	// Fixed parts: indicator(2) + checkbox(4) + badges(3) + dot(2) + spacing(8) + padding(4)
	fixed := 23
	available := a.width - fixed
	if available < 30 {
		available = 30
	}

	switch {
	case a.width < 80:
		// Compact: no user column
		a.cols = ColumnWidths{Port: 5, PID: 6, Process: available - 11, User: 0}
	case a.width < 120:
		// Normal
		procW := available - 22
		if procW < 12 {
			procW = 12
		}
		a.cols = ColumnWidths{Port: 6, PID: 7, Process: procW, User: 8}
	default:
		// Wide
		procW := available - 28
		if procW > 35 {
			procW = 35
		}
		a.cols = ColumnWidths{Port: 7, PID: 8, Process: procW, User: 10}
	}

	a.colsWidth = a.width
}

// Selection helpers

// ToggleSelection toggles selection for the current item
func (a *App) ToggleSelection(idx int) {
	if a.selection[idx] {
		delete(a.selection, idx)
	} else {
		a.selection[idx] = true
	}
}

// ClearSelection clears all selections
func (a *App) ClearSelection() {
	a.selection = make(map[int]bool)
}

// SelectAll selects all filtered items
func (a *App) SelectAll() {
	for i := range a.filtered {
		a.selection[i] = true
	}
}

// SelectionCount returns the number of selected items
func (a *App) SelectionCount() int {
	return len(a.selection)
}

// IsSelected checks if an item is selected
func (a *App) IsSelected(idx int) bool {
	return a.selection[idx]
}

// GetSelectedPorts returns all selected ports
func (a *App) GetSelectedPorts() []PortItem {
	if len(a.selection) == 0 && len(a.filtered) > 0 && a.cursor < len(a.filtered) {
		// If nothing selected, return current item
		return []PortItem{a.filtered[a.cursor]}
	}

	var selected []PortItem
	for idx := range a.selection {
		if idx < len(a.filtered) {
			selected = append(selected, a.filtered[idx])
		}
	}
	return selected
}

// Cursor helpers

// moveCursor moves the selection cursor
func (a *App) moveCursor(delta int) {
	a.cursor += delta
	if a.cursor < 0 {
		a.cursor = 0
	}
	if a.cursor >= len(a.filtered) {
		a.cursor = len(a.filtered) - 1
	}
	if a.cursor < 0 {
		a.cursor = 0
	}
}

// Status helpers

// setStatus sets a temporary status message
func (a *App) setStatus(text string, isError bool) {
	a.statusText = text
	a.statusError = isError
	a.statusExpiry = time.Now().Add(3 * time.Second)
}

// clearStatus clears the status message
func (a *App) clearStatus() {
	a.statusText = ""
	a.statusError = false
}
