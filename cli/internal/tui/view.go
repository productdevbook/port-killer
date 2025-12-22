package tui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/productdevbook/port-killer/cli/internal/tui/theme"
)

// View renders the TUI
func (a *App) View() string {
	if a.width == 0 {
		return ""
	}

	switch a.viewMode {
	case ViewCommandPalette:
		return a.viewCommandPalette()
	case ViewLogViewer:
		return a.viewLogViewer()
	case ViewExportDialog:
		return a.viewExportDialog()
	case ViewHelp:
		return a.viewHelp()
	case ViewDetail:
		return a.viewDetail()
	case ViewConfirmKill:
		return a.viewConfirmKill()
	default:
		return a.viewList()
	}
}

// viewList renders the main port list
func (a *App) viewList() string {
	t := theme.Current()
	var b strings.Builder

	// Header
	b.WriteString(a.renderHeader())

	// Search (if active)
	if a.searching {
		b.WriteString("  " + t.TextMuted().Render("search:") + " " + a.searchInput.View() + "\n")
	}

	// Port list
	b.WriteString(a.renderPortList())

	// Footer
	b.WriteString(a.renderFooter())

	return b.String()
}

// renderHeader renders the header
func (a *App) renderHeader() string {
	t := theme.Current()

	// Logo
	logo := t.Logo().Render("●") + " " + t.LogoText().Render("PortKiller")

	// Stats
	var stats string
	if a.loading {
		stats = a.spinner.View() + " " + t.TextMuted().Render("scanning")
	} else {
		count := fmt.Sprintf("%d", len(a.filtered))
		if a.SelectionCount() > 0 {
			count = fmt.Sprintf("%d/%d", a.SelectionCount(), len(a.filtered))
		}
		stats = t.TextSecondary().Render(count) + " " + t.TextMuted().Render("ports")
	}

	// Spacing
	space := a.width - lipgloss.Width(logo) - lipgloss.Width(stats) - 4
	if space < 1 {
		space = 1
	}

	return "\n  " + logo + strings.Repeat(" ", space) + stats + "\n\n"
}

// renderPortList renders the port table
func (a *App) renderPortList() string {
	t := theme.Current()

	if len(a.filtered) == 0 {
		empty := t.TextMuted().Render("No listening ports")
		return lipgloss.Place(a.width, 5, lipgloss.Center, lipgloss.Center, empty)
	}

	var b strings.Builder

	// Calculate visible range
	listHeight := a.height - 8
	if a.searching {
		listHeight--
	}
	if listHeight < 3 {
		listHeight = 3
	}

	start, end := 0, len(a.filtered)
	if end > listHeight {
		half := listHeight / 2
		if a.cursor > half {
			start = a.cursor - half
		}
		end = start + listHeight
		if end > len(a.filtered) {
			end = len(a.filtered)
			start = end - listHeight
			if start < 0 {
				start = 0
			}
		}
	}

	// Header row
	cols := a.cols
	var hdr string
	if cols.User > 0 {
		hdr = fmt.Sprintf("        %-*s %-*s %-*s %-*s",
			cols.Port, "PORT", cols.PID, "PID", cols.Process, "PROCESS", cols.User, "USER")
	} else {
		hdr = fmt.Sprintf("        %-*s %-*s %-*s",
			cols.Port, "PORT", cols.PID, "PID", cols.Process, "PROCESS")
	}
	b.WriteString(t.Header().Render(hdr) + "\n")

	// Rows
	for i := start; i < end; i++ {
		b.WriteString(a.renderRow(a.filtered[i], i == a.cursor, a.IsSelected(i)) + "\n")
	}

	return b.String()
}

// renderRow renders a single port row
func (a *App) renderRow(item PortItem, cursor bool, selected bool) string {
	t := theme.Current()
	cols := a.cols

	// Cursor indicator
	cursorStr := "  "
	if cursor {
		cursorStr = t.Cursor().Render("› ")
	}

	// Selection checkbox
	checkbox := "[ ] "
	if selected {
		checkbox = t.AccentStyle().Render("[x] ")
	}

	// Badges
	var badge string
	if item.IsFavorite && item.IsWatched {
		badge = t.Favorite().Render("★") + t.Watched().Render("◉")
	} else if item.IsFavorite {
		badge = t.Favorite().Render("★") + " "
	} else if item.IsWatched {
		badge = " " + t.Watched().Render("◉")
	} else {
		badge = "  "
	}

	// Process name (truncate)
	proc := item.Port.Process
	if len(proc) > cols.Process {
		proc = proc[:cols.Process-1] + "…"
	}

	// User
	user := item.Port.User
	if user == "" {
		user = "-"
	}
	if cols.User > 0 && len(user) > cols.User {
		user = user[:cols.User-1] + "…"
	}

	// Type dot
	dot := t.ProcessType(item.Type).Render("●")

	// Build row
	var row string
	if cols.User > 0 {
		row = fmt.Sprintf("%-*d %-*d %-*s %-*s %s",
			cols.Port, item.Port.Port,
			cols.PID, item.Port.PID,
			cols.Process, proc,
			cols.User, user,
			dot)
	} else {
		row = fmt.Sprintf("%-*d %-*d %-*s %s",
			cols.Port, item.Port.Port,
			cols.PID, item.Port.PID,
			cols.Process, proc,
			dot)
	}

	// Style
	if cursor {
		row = t.Selected().Render(row)
	} else if selected {
		row = t.AccentStyle().Render(row)
	} else if item.IsFavorite {
		row = t.Favorite().Render(row)
	} else if item.IsWatched {
		row = t.Watched().Render(row)
	} else {
		row = t.TextPrimary().Render(row)
	}

	return cursorStr + checkbox + badge + " " + row
}

// renderFooter renders the footer
func (a *App) renderFooter() string {
	t := theme.Current()

	// Status message
	var status string
	if a.statusText != "" && time.Now().Before(a.statusExpiry) {
		if a.statusError {
			status = t.ErrorMsg().Render("✗ " + a.statusText)
		} else {
			status = t.SuccessMsg().Render("✓ " + a.statusText)
		}
	} else {
		// Sort indicator
		var sort string
		switch a.sortMode {
		case SortByFavorites:
			sort = "★ favorites"
		case SortByPort:
			sort = "# port"
		case SortByName:
			sort = "A-Z name"
		}
		status = t.TextMuted().Render(sort)
	}

	// Help hints
	hints := []string{
		t.HelpKey().Render("j/k") + t.HelpDesc().Render(" move"),
		t.HelpKey().Render("/") + t.HelpDesc().Render(" commands"),
		t.HelpKey().Render("space") + t.HelpDesc().Render(" select"),
		t.HelpKey().Render("x") + t.HelpDesc().Render(" kill"),
		t.HelpKey().Render("?") + t.HelpDesc().Render(" help"),
	}

	return "\n  " + status + "\n  " + strings.Join(hints, "   ") + "\n"
}

// viewCommandPalette renders the command palette
func (a *App) viewCommandPalette() string {
	t := theme.Current()

	// Build command list
	var listContent strings.Builder

	// Input field
	listContent.WriteString("  " + t.TextMuted().Render("/") + " " + a.paletteInput.View() + "\n\n")

	// Commands
	maxVisible := 10
	if len(a.paletteFiltered) < maxVisible {
		maxVisible = len(a.paletteFiltered)
	}

	start := 0
	if a.paletteCursor >= maxVisible {
		start = a.paletteCursor - maxVisible + 1
	}
	end := start + maxVisible
	if end > len(a.paletteFiltered) {
		end = len(a.paletteFiltered)
	}

	for i := start; i < end; i++ {
		cmd := a.paletteFiltered[i]
		cursor := "  "
		if i == a.paletteCursor {
			cursor = t.Cursor().Render("› ")
		}

		name := t.AccentStyle().Render(cmd.Name)
		title := t.TextPrimary().Render(" " + cmd.Title)
		shortcut := ""
		if cmd.Shortcut != "" {
			shortcut = t.TextMuted().Render(" [" + cmd.Shortcut + "]")
		}

		if i == a.paletteCursor {
			name = t.Selected().Render(cmd.Name)
			title = t.Selected().Render(" " + cmd.Title)
		}

		listContent.WriteString(cursor + name + title + shortcut + "\n")
	}

	// Footer hint
	listContent.WriteString("\n  " + t.TextMuted().Render("↑↓ navigate  ↵ select  esc close"))

	// Create dialog
	dialogWidth := 50
	if a.width < 60 {
		dialogWidth = a.width - 10
	}

	dialog := t.DialogBorder().Width(dialogWidth).Render(listContent.String())

	// Center on screen
	return lipgloss.Place(a.width, a.height, lipgloss.Center, lipgloss.Center, dialog)
}

// viewLogViewer renders the log viewer
func (a *App) viewLogViewer() string {
	if a.logViewer == nil || a.logViewerPort == nil {
		return a.viewList()
	}

	t := theme.Current()
	var b strings.Builder

	// Header
	port := a.logViewerPort
	header := t.LogoText().Render(fmt.Sprintf("Logs: Port %d (%s)", port.Port.Port, port.Port.Process))
	b.WriteString("\n  " + header + "\n\n")

	// Log entries
	entries := a.logViewer.entries

	// Apply filter
	if a.logViewer.filter >= 0 {
		var filtered []LogEntry
		for _, e := range entries {
			if e.Source == a.logViewer.filter {
				filtered = append(filtered, e)
			}
		}
		entries = filtered
	}

	// Calculate visible range
	logHeight := a.height - 10
	if logHeight < 5 {
		logHeight = 5
	}

	start := a.logViewer.scroll
	if start < 0 {
		start = 0
	}
	end := start + logHeight
	if end > len(entries) {
		end = len(entries)
	}
	if a.logViewer.follow && len(entries) > logHeight {
		start = len(entries) - logHeight
		end = len(entries)
		a.logViewer.scroll = start
	}

	// Render entries
	if len(entries) == 0 {
		b.WriteString("  " + t.TextMuted().Render("No log entries") + "\n")
	} else {
		for i := start; i < end; i++ {
			entry := entries[i]
			timeStr := entry.Time.Format("15:04:05")

			var sourceStyle lipgloss.Style
			switch entry.Source {
			case LogSourceNetwork:
				sourceStyle = t.InfoStyle()
			case LogSourceStdout:
				sourceStyle = t.SuccessMsg()
			case LogSourceStderr:
				sourceStyle = t.ErrorMsg()
			default:
				sourceStyle = t.TextMuted()
			}

			line := fmt.Sprintf("  %s %s %s",
				t.TextMuted().Render(timeStr),
				sourceStyle.Render(fmt.Sprintf("[%s]", entry.Source.String())),
				t.TextPrimary().Render(entry.Content))

			// Truncate if too long
			if lipgloss.Width(line) > a.width-4 {
				line = line[:a.width-7] + "..."
			}

			b.WriteString(line + "\n")
		}
	}

	// Footer
	follow := "off"
	if a.logViewer.follow {
		follow = "on"
	}

	filterStr := "all"
	switch a.logViewer.filter {
	case LogSourceNetwork:
		filterStr = "network"
	case LogSourceStdout:
		filterStr = "stdout"
	case LogSourceStderr:
		filterStr = "stderr"
	}

	hints := []string{
		t.HelpKey().Render("j/k") + t.HelpDesc().Render(" scroll"),
		t.HelpKey().Render("f") + t.HelpDesc().Render(" follow:"+follow),
		t.HelpKey().Render("1-4") + t.HelpDesc().Render(" filter:"+filterStr),
		t.HelpKey().Render("c") + t.HelpDesc().Render(" copy"),
		t.HelpKey().Render("esc") + t.HelpDesc().Render(" close"),
	}

	b.WriteString("\n  " + strings.Join(hints, "   ") + "\n")

	return b.String()
}

// viewExportDialog renders the export format dialog
func (a *App) viewExportDialog() string {
	t := theme.Current()

	var listContent strings.Builder
	listContent.WriteString("  " + t.LogoText().Render("Copy to Clipboard") + "\n\n")
	listContent.WriteString("  " + t.TextMuted().Render("Select format:") + "\n\n")

	for i, format := range a.exportFormats {
		cursor := "  "
		if i == a.exportCursor {
			cursor = t.Cursor().Render("› ")
		}

		name := format.String()
		if i == a.exportCursor {
			name = t.Selected().Render(name)
		} else {
			name = t.TextPrimary().Render(name)
		}

		listContent.WriteString(cursor + name + "\n")
	}

	listContent.WriteString("\n  " + t.TextMuted().Render("↑↓ select  ↵ copy  esc cancel"))

	dialog := t.DialogBorder().Width(35).Render(listContent.String())
	return lipgloss.Place(a.width, a.height, lipgloss.Center, lipgloss.Center, dialog)
}

// viewDetail renders the detail view
func (a *App) viewDetail() string {
	if len(a.filtered) == 0 || a.cursor >= len(a.filtered) {
		return "No port selected"
	}

	t := theme.Current()
	item := a.filtered[a.cursor]

	var b strings.Builder
	b.WriteString("\n  " + t.LogoText().Render("Port Details") + "\n\n")

	details := []struct{ k, v string }{
		{"Port", fmt.Sprintf("%d", item.Port.Port)},
		{"PID", fmt.Sprintf("%d", item.Port.PID)},
		{"Process", item.Port.Process},
		{"User", item.Port.User},
		{"Address", item.Port.Address},
		{"Type", item.Type},
		{"Favorite", fmt.Sprintf("%v", item.IsFavorite)},
		{"Watched", fmt.Sprintf("%v", item.IsWatched)},
	}

	for _, d := range details {
		b.WriteString(fmt.Sprintf("  %s %s\n",
			t.TextMuted().Width(12).Render(d.k+":"),
			t.TextPrimary().Render(d.v)))
	}

	b.WriteString("\n  " + t.TextMuted().Render("ESC back  x kill  L logs  c copy"))
	return b.String()
}

// viewConfirmKill renders the kill confirmation dialog
func (a *App) viewConfirmKill() string {
	if a.pendingKill == nil {
		return a.viewList()
	}

	t := theme.Current()
	item := a.pendingKill

	action := "Kill"
	if a.pendingForceKill {
		action = "Force Kill"
	}

	content := fmt.Sprintf(
		"%s process on port %s?\n\n"+
			"  Process: %s\n"+
			"  PID: %d\n\n"+
			"%s    %s",
		t.WarningMsg().Render(action),
		t.Logo().Render(fmt.Sprintf("%d", item.Port.Port)),
		item.Port.Process,
		item.Port.PID,
		t.HelpKey().Render(" y ")+" "+t.HelpDesc().Render("yes"),
		t.HelpKey().Render(" n ")+" "+t.HelpDesc().Render("no"),
	)

	dialog := t.DialogDanger().Width(45).Render(content)
	return lipgloss.Place(a.width, a.height, lipgloss.Center, lipgloss.Center, dialog)
}

// viewHelp renders the help view
func (a *App) viewHelp() string {
	t := theme.Current()
	var b strings.Builder

	b.WriteString("\n  " + t.LogoText().Render("Keyboard Shortcuts") + "\n\n")

	sections := []struct {
		title string
		keys  []struct{ k, d string }
	}{
		{"Navigation", []struct{ k, d string }{
			{"j/↓", "down"}, {"k/↑", "up"}, {"g", "top"}, {"G", "bottom"},
		}},
		{"Actions", []struct{ k, d string }{
			{"x", "kill"}, {"X", "force kill"}, {"f", "favorite"}, {"w", "watch"}, {"r", "refresh"},
		}},
		{"Selection", []struct{ k, d string }{
			{"space", "toggle select"}, {"ctrl+a", "select all"},
		}},
		{"Views", []struct{ k, d string }{
			{"/", "commands"}, {"Enter", "details"}, {"L", "logs"}, {"c", "copy"},
		}},
		{"Sort", []struct{ k, d string }{
			{"1", "by port"}, {"2", "by name"}, {"t", "group type"},
		}},
	}

	for _, s := range sections {
		b.WriteString("  " + t.TextSecondary().Render(s.title) + "\n")
		for _, k := range s.keys {
			b.WriteString(fmt.Sprintf("    %s %s\n",
				t.HelpKey().Width(10).Render(k.k),
				t.HelpDesc().Render(k.d)))
		}
		b.WriteString("\n")
	}

	// Process type legend
	b.WriteString("  " + t.TextSecondary().Render("Process Types") + "\n")
	types := []struct {
		ptype string
		desc  string
	}{
		{"WebServer", "nginx, apache, node http"},
		{"Database", "mysql, postgres, redis, mongo"},
		{"Development", "webpack, vite, npm, go"},
		{"System", "system services"},
		{"Other", "other processes"},
	}
	for _, pt := range types {
		dot := t.ProcessType(pt.ptype).Render("●")
		b.WriteString(fmt.Sprintf("    %s %s\n", dot, t.HelpDesc().Render(pt.desc)))
	}
	b.WriteString("\n")

	// Icons legend
	b.WriteString("  " + t.TextSecondary().Render("Icons") + "\n")
	b.WriteString(fmt.Sprintf("    %s %s\n", t.Favorite().Render("★"), t.HelpDesc().Render("favorite")))
	b.WriteString(fmt.Sprintf("    %s %s\n", t.Watched().Render("◉"), t.HelpDesc().Render("watched")))
	b.WriteString("\n")

	b.WriteString("  " + t.TextMuted().Render("Press ? or ESC to close"))
	return b.String()
}
