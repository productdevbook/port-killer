package tui

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

// exportToClipboard exports selected ports to clipboard
func (a *App) exportToClipboard(format ExportFormat) tea.Cmd {
	ports := a.GetSelectedPorts()
	if len(ports) == 0 {
		return func() tea.Msg {
			return statusMsg{text: "No ports to export", isError: true}
		}
	}

	content := FormatPorts(ports, format)
	return CopyToClipboard(content)
}

// FormatPorts formats ports to the specified format
func FormatPorts(ports []PortItem, format ExportFormat) string {
	switch format {
	case FormatPlain:
		return formatPlain(ports)
	case FormatMarkdown:
		return formatMarkdown(ports)
	case FormatJSON:
		return formatJSON(ports)
	case FormatCSV:
		return formatCSV(ports)
	default:
		return formatPlain(ports)
	}
}

// formatPlain formats ports as plain text
func formatPlain(ports []PortItem) string {
	var b strings.Builder
	b.WriteString("PORT\tPID\tPROCESS\tUSER\n")
	b.WriteString(strings.Repeat("-", 50) + "\n")

	for _, p := range ports {
		b.WriteString(fmt.Sprintf("%d\t%d\t%s\t%s\n",
			p.Port.Port, p.Port.PID, p.Port.Process, p.Port.User))
	}
	return b.String()
}

// formatMarkdown formats ports as a markdown table
func formatMarkdown(ports []PortItem) string {
	var b strings.Builder
	b.WriteString("| Port | PID | Process | User | Type |\n")
	b.WriteString("|------|-----|---------|------|------|\n")

	for _, p := range ports {
		fav := ""
		if p.IsFavorite {
			fav = " ★"
		}
		b.WriteString(fmt.Sprintf("| %d%s | %d | %s | %s | %s |\n",
			p.Port.Port, fav, p.Port.PID, p.Port.Process, p.Port.User, p.Type))
	}
	return b.String()
}

// formatJSON formats ports as JSON
func formatJSON(ports []PortItem) string {
	type portJSON struct {
		Port       int    `json:"port"`
		PID        int    `json:"pid"`
		Process    string `json:"process"`
		User       string `json:"user"`
		Address    string `json:"address"`
		Type       string `json:"type"`
		IsFavorite bool   `json:"is_favorite"`
		IsWatched  bool   `json:"is_watched"`
	}

	data := make([]portJSON, len(ports))
	for i, p := range ports {
		data[i] = portJSON{
			Port:       p.Port.Port,
			PID:        p.Port.PID,
			Process:    p.Port.Process,
			User:       p.Port.User,
			Address:    p.Port.Address,
			Type:       p.Type,
			IsFavorite: p.IsFavorite,
			IsWatched:  p.IsWatched,
		}
	}

	result, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return "{}"
	}
	return string(result)
}

// formatCSV formats ports as CSV
func formatCSV(ports []PortItem) string {
	var b strings.Builder
	w := csv.NewWriter(&b)

	// Header
	w.Write([]string{"port", "pid", "process", "user", "address", "type", "favorite", "watched"})

	// Data
	for _, p := range ports {
		w.Write([]string{
			fmt.Sprintf("%d", p.Port.Port),
			fmt.Sprintf("%d", p.Port.PID),
			p.Port.Process,
			p.Port.User,
			p.Port.Address,
			p.Type,
			fmt.Sprintf("%v", p.IsFavorite),
			fmt.Sprintf("%v", p.IsWatched),
		})
	}

	w.Flush()
	return b.String()
}

// CopyToClipboard copies text to clipboard
func CopyToClipboard(text string) tea.Cmd {
	return func() tea.Msg {
		err := writeToNativeClipboard(text)
		return clipboardCopiedMsg{success: err == nil, err: err}
	}
}

// writeToNativeClipboard writes to the native system clipboard using pbcopy (macOS)
func writeToNativeClipboard(text string) error {
	cmd := exec.Command("pbcopy")
	cmd.Stdin = strings.NewReader(text)
	return cmd.Run()
}
