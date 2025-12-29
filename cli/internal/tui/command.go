package tui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/sahilm/fuzzy"
)

// CommandCategory represents a command category
type CommandCategory string

const (
	CategoryAction CommandCategory = "Actions"
	CategoryView   CommandCategory = "View"
	CategorySort   CommandCategory = "Sort"
	CategoryExport CommandCategory = "Export"
)

// Command represents a slash command
type Command struct {
	ID          string
	Name        string // e.g., "/kill"
	Title       string // e.g., "Kill Process"
	Description string
	Shortcut    string // e.g., "x"
	Category    CommandCategory
	Handler     func(a *App) tea.Cmd
	Enabled     func(a *App) bool
}

// CommandRegistry holds all available commands
type CommandRegistry struct {
	commands []Command
}

// NewCommandRegistry creates a new command registry
func NewCommandRegistry() *CommandRegistry {
	return &CommandRegistry{
		commands: GetBuiltinCommands(),
	}
}

// Filter filters commands based on query
func (r *CommandRegistry) Filter(query string) []Command {
	if query == "" {
		return r.commands
	}

	// Remove leading "/" for matching
	query = strings.TrimPrefix(query, "/")

	// Build searchable strings
	var items []string
	for _, cmd := range r.commands {
		items = append(items, cmd.Name+" "+cmd.Title+" "+cmd.Description)
	}

	// Fuzzy search
	matches := fuzzy.Find(query, items)

	var filtered []Command
	for _, match := range matches {
		filtered = append(filtered, r.commands[match.Index])
	}
	return filtered
}

// Execute executes a command by ID
func (r *CommandRegistry) Execute(id string, a *App) tea.Cmd {
	for _, cmd := range r.commands {
		if cmd.ID == id {
			if cmd.Enabled != nil && !cmd.Enabled(a) {
				return nil
			}
			if cmd.Handler != nil {
				return cmd.Handler(a)
			}
			return nil
		}
	}
	return nil
}

// GetBuiltinCommands returns all built-in commands
func GetBuiltinCommands() []Command {
	return []Command{
		// Actions
		{
			ID:          "kill",
			Name:        "/kill",
			Title:       "Kill Process",
			Description: "Terminate the selected process (SIGTERM)",
			Shortcut:    "x",
			Category:    CategoryAction,
			Handler:     cmdKill,
			Enabled:     hasSelection,
		},
		{
			ID:          "force-kill",
			Name:        "/force-kill",
			Title:       "Force Kill",
			Description: "Force terminate the selected process (SIGKILL)",
			Shortcut:    "X",
			Category:    CategoryAction,
			Handler:     cmdForceKill,
			Enabled:     hasSelection,
		},
		{
			ID:          "favorite",
			Name:        "/favorite",
			Title:       "Toggle Favorite",
			Description: "Add or remove port from favorites",
			Shortcut:    "f",
			Category:    CategoryAction,
			Handler:     cmdFavorite,
			Enabled:     hasSelection,
		},
		{
			ID:          "watch",
			Name:        "/watch",
			Title:       "Toggle Watch",
			Description: "Start or stop watching port",
			Shortcut:    "w",
			Category:    CategoryAction,
			Handler:     cmdWatch,
			Enabled:     hasSelection,
		},
		{
			ID:          "refresh",
			Name:        "/refresh",
			Title:       "Refresh Ports",
			Description: "Rescan all listening ports",
			Shortcut:    "r",
			Category:    CategoryAction,
			Handler:     cmdRefresh,
		},

		// View
		{
			ID:          "logs",
			Name:        "/logs",
			Title:       "View Logs",
			Description: "Show logs and connections for selected port",
			Shortcut:    "L",
			Category:    CategoryView,
			Handler:     cmdLogs,
			Enabled:     hasSelection,
		},
		{
			ID:          "detail",
			Name:        "/detail",
			Title:       "Port Details",
			Description: "Show detailed info for selected port",
			Shortcut:    "Enter",
			Category:    CategoryView,
			Handler:     cmdDetail,
			Enabled:     hasSelection,
		},
		{
			ID:          "help",
			Name:        "/help",
			Title:       "Show Help",
			Description: "Display keyboard shortcuts and help",
			Shortcut:    "?",
			Category:    CategoryView,
			Handler:     cmdHelp,
		},
		{
			ID:          "filter",
			Name:        "/filter",
			Title:       "Filter Ports",
			Description: "Search and filter port list",
			Shortcut:    "/",
			Category:    CategoryView,
			Handler:     cmdFilter,
		},

		// Sort
		{
			ID:          "sort-favorites",
			Name:        "/sort favorites",
			Title:       "Sort by Favorites",
			Description: "Show favorites first",
			Shortcut:    "0",
			Category:    CategorySort,
			Handler:     cmdSortFavorites,
		},
		{
			ID:          "sort-port",
			Name:        "/sort port",
			Title:       "Sort by Port",
			Description: "Sort by port number",
			Shortcut:    "1",
			Category:    CategorySort,
			Handler:     cmdSortPort,
		},
		{
			ID:          "sort-name",
			Name:        "/sort name",
			Title:       "Sort by Name",
			Description: "Sort by process name",
			Shortcut:    "2",
			Category:    CategorySort,
			Handler:     cmdSortName,
		},

		// Export
		{
			ID:          "copy",
			Name:        "/copy",
			Title:       "Copy to Clipboard",
			Description: "Copy selected ports to clipboard",
			Shortcut:    "c",
			Category:    CategoryExport,
			Handler:     cmdCopy,
			Enabled:     hasSelection,
		},
		{
			ID:          "export",
			Name:        "/export",
			Title:       "Export to File",
			Description: "Export ports to file (JSON, CSV, Markdown)",
			Shortcut:    "e",
			Category:    CategoryExport,
			Handler:     cmdExport,
		},
	}
}

// Command handlers

func hasSelection(a *App) bool {
	return len(a.filtered) > 0 && a.cursor < len(a.filtered)
}

func cmdKill(a *App) tea.Cmd {
	if len(a.filtered) == 0 || a.cursor >= len(a.filtered) {
		return nil
	}
	item := a.filtered[a.cursor]
	a.pendingKill = &item
	a.pendingForceKill = false
	a.viewMode = ViewConfirmKill
	return nil
}

func cmdForceKill(a *App) tea.Cmd {
	if len(a.filtered) == 0 || a.cursor >= len(a.filtered) {
		return nil
	}
	item := a.filtered[a.cursor]
	a.pendingKill = &item
	a.pendingForceKill = true
	a.viewMode = ViewConfirmKill
	return nil
}

func cmdFavorite(a *App) tea.Cmd {
	if len(a.filtered) == 0 || a.cursor >= len(a.filtered) {
		return nil
	}
	// Handler will be implemented in update.go
	return func() tea.Msg {
		return commandExecutedMsg{id: "favorite"}
	}
}

func cmdWatch(a *App) tea.Cmd {
	if len(a.filtered) == 0 || a.cursor >= len(a.filtered) {
		return nil
	}
	return func() tea.Msg {
		return commandExecutedMsg{id: "watch"}
	}
}

func cmdRefresh(a *App) tea.Cmd {
	a.loading = true
	return tea.Batch(a.loadPorts(), a.spinner.Tick)
}

func cmdLogs(a *App) tea.Cmd {
	if len(a.filtered) == 0 || a.cursor >= len(a.filtered) {
		return nil
	}
	item := a.filtered[a.cursor]
	return func() tea.Msg {
		return logViewerOpenMsg{port: item}
	}
}

func cmdDetail(a *App) tea.Cmd {
	if len(a.filtered) > 0 {
		a.viewMode = ViewDetail
	}
	return nil
}

func cmdHelp(a *App) tea.Cmd {
	a.viewMode = ViewHelp
	return nil
}

func cmdFilter(a *App) tea.Cmd {
	a.searching = true
	a.searchInput.Focus()
	return nil
}

func cmdSortFavorites(a *App) tea.Cmd {
	a.sortMode = SortByFavorites
	a.updateFilteredPorts()
	a.setStatus("Sorted by favorites", false)
	return nil
}

func cmdSortPort(a *App) tea.Cmd {
	a.sortMode = SortByPort
	a.updateFilteredPorts()
	a.setStatus("Sorted by port", false)
	return nil
}

func cmdSortName(a *App) tea.Cmd {
	a.sortMode = SortByName
	a.updateFilteredPorts()
	a.setStatus("Sorted by name", false)
	return nil
}

func cmdCopy(a *App) tea.Cmd {
	a.viewMode = ViewExportDialog
	a.exportActive = true
	a.exportCursor = 0
	return nil
}

func cmdExport(a *App) tea.Cmd {
	a.viewMode = ViewExportDialog
	a.exportActive = true
	a.exportCursor = 0
	return nil
}
