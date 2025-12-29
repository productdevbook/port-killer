package tui

import (
	"time"

	"github.com/productdevbook/port-killer/cli/internal/scanner"
)

// ViewMode represents the current view mode
type ViewMode int

const (
	ViewList ViewMode = iota
	ViewDetail
	ViewHelp
	ViewConfirmKill
	ViewCommandPalette
	ViewLogViewer
	ViewExportDialog
)

// SortMode represents the sorting method
type SortMode int

const (
	SortByFavorites SortMode = iota
	SortByPort
	SortByName
)

// PortItem wraps a port with display info
type PortItem struct {
	Port       scanner.Port
	IsFavorite bool
	IsWatched  bool
	Type       string
}

// ColumnWidths holds cached responsive column widths
type ColumnWidths struct {
	Port    int
	PID     int
	Process int
	User    int
}

// LogSource represents the source of a log entry
type LogSource int

const (
	LogSourceNetwork LogSource = iota
	LogSourceStdout
	LogSourceStderr
)

// String returns the display string for a log source
func (s LogSource) String() string {
	switch s {
	case LogSourceNetwork:
		return "NET"
	case LogSourceStdout:
		return "OUT"
	case LogSourceStderr:
		return "ERR"
	default:
		return "???"
	}
}

// LogEntry represents a single log entry
type LogEntry struct {
	Time    time.Time
	Source  LogSource
	Content string
}

// ExportFormat represents an export format
type ExportFormat int

const (
	FormatPlain ExportFormat = iota
	FormatMarkdown
	FormatJSON
	FormatCSV
)

// String returns the display name for an export format
func (f ExportFormat) String() string {
	switch f {
	case FormatPlain:
		return "Plain Text"
	case FormatMarkdown:
		return "Markdown"
	case FormatJSON:
		return "JSON"
	case FormatCSV:
		return "CSV"
	default:
		return "Unknown"
	}
}

// AllExportFormats returns all available export formats
func AllExportFormats() []ExportFormat {
	return []ExportFormat{FormatPlain, FormatMarkdown, FormatJSON, FormatCSV}
}
