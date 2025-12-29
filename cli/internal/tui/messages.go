package tui

import (
	"time"

	"github.com/productdevbook/port-killer/cli/internal/config"
	"github.com/productdevbook/port-killer/cli/internal/scanner"
)

// Core message types

// portsLoadedMsg is sent when port scanning completes
type portsLoadedMsg struct {
	ports []scanner.Port
	err   error
}

// portKilledMsg is sent when a process kill completes
type portKilledMsg struct {
	port int
	err  error
}

// configLoadedMsg is sent when config loading completes
type configLoadedMsg struct {
	config *config.Config
}

// tickMsg is sent for auto-refresh timing
type tickMsg time.Time

// Command palette messages

// commandPaletteOpenMsg opens the command palette
type commandPaletteOpenMsg struct{}

// commandPaletteCloseMsg closes the command palette
type commandPaletteCloseMsg struct{}

// commandExecutedMsg is sent when a command completes
type commandExecutedMsg struct {
	id  string
	err error
}

// Log viewer messages

// logViewerOpenMsg opens the log viewer for a port
type logViewerOpenMsg struct {
	port PortItem
}

// logViewerCloseMsg closes the log viewer
type logViewerCloseMsg struct{}

// logEntryMsg adds a log entry
type logEntryMsg struct {
	entry LogEntry
}

// logEntriesLoadedMsg is sent when log entries are loaded
type logEntriesLoadedMsg struct {
	entries []LogEntry
	err     error
}

// Export messages

// exportDialogOpenMsg opens the export format dialog
type exportDialogOpenMsg struct{}

// exportDialogCloseMsg closes the export dialog
type exportDialogCloseMsg struct{}

// exportFormatSelectedMsg is sent when a format is selected
type exportFormatSelectedMsg struct {
	format ExportFormat
}

// clipboardCopiedMsg is sent when content is copied to clipboard
type clipboardCopiedMsg struct {
	success bool
	err     error
}

// Selection messages

// selectionToggleMsg toggles selection for an item
type selectionToggleMsg struct {
	index int
}

// selectionClearMsg clears all selections
type selectionClearMsg struct{}

// selectionAllMsg selects all items
type selectionAllMsg struct{}

// Status messages

// statusMsg sets a temporary status message
type statusMsg struct {
	text    string
	isError bool
}

// clearStatusMsg clears the status message
type clearStatusMsg struct{}
