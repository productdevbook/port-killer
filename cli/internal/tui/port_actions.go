package tui

import (
	"fmt"
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/productdevbook/port-killer/cli/internal/config"
	"github.com/productdevbook/port-killer/cli/internal/scanner"
	"github.com/sahilm/fuzzy"
)

// updatePorts updates the port list from scanned ports
func (a *App) updatePorts(ports []scanner.Port) {
	a.ports = make([]PortItem, len(ports))
	for i, p := range ports {
		a.ports[i] = PortItem{
			Port:       p,
			IsFavorite: a.config != nil && a.config.IsFavorite(p.Port),
			IsWatched:  a.config != nil && a.config.IsWatched(p.Port),
			Type:       detectProcessType(p.Process),
		}
	}
	a.updateFilteredPorts()
}

// updateFilteredPorts applies sorting and grouping
func (a *App) updateFilteredPorts() {
	a.filtered = make([]PortItem, len(a.ports))
	copy(a.filtered, a.ports)

	// Update favorite/watched status
	for i := range a.filtered {
		if a.config != nil {
			a.filtered[i].IsFavorite = a.config.IsFavorite(a.filtered[i].Port.Port)
			a.filtered[i].IsWatched = a.config.IsWatched(a.filtered[i].Port.Port)
		}
	}

	// Sort
	sort.Slice(a.filtered, func(i, j int) bool {
		switch a.sortMode {
		case SortByFavorites:
			if a.filtered[i].IsFavorite != a.filtered[j].IsFavorite {
				return a.filtered[i].IsFavorite
			}
			return a.filtered[i].Port.Port < a.filtered[j].Port.Port
		case SortByPort:
			return a.filtered[i].Port.Port < a.filtered[j].Port.Port
		case SortByName:
			return a.filtered[i].Port.Process < a.filtered[j].Port.Process
		}
		return a.filtered[i].Port.Port < a.filtered[j].Port.Port
	})

	// Ensure cursor is valid
	if a.cursor >= len(a.filtered) {
		a.cursor = len(a.filtered) - 1
	}
	if a.cursor < 0 {
		a.cursor = 0
	}

	// Clear selection if filtered list changed significantly
	// Keep only valid selections
	newSelection := make(map[int]bool)
	for idx := range a.selection {
		if idx < len(a.filtered) {
			newSelection[idx] = true
		}
	}
	a.selection = newSelection
}

// filterPorts filters ports based on search query
func (a *App) filterPorts(query string) {
	if query == "" {
		a.updateFilteredPorts()
		return
	}

	// Create searchable strings
	var items []string
	for _, p := range a.ports {
		items = append(items, fmt.Sprintf("%d %s %s", p.Port.Port, p.Port.Process, p.Port.User))
	}

	// Fuzzy search
	matches := fuzzy.Find(query, items)

	a.filtered = make([]PortItem, len(matches))
	for i, match := range matches {
		a.filtered[i] = a.ports[match.Index]
	}

	a.cursor = 0
	a.ClearSelection()
}

// killSelected shows kill confirmation for the selected process
func (a *App) killSelected(force bool) (tea.Model, tea.Cmd) {
	if len(a.filtered) == 0 || a.cursor >= len(a.filtered) {
		return a, nil
	}

	item := a.filtered[a.cursor]
	a.pendingKill = &item
	a.pendingForceKill = force
	a.viewMode = ViewConfirmKill
	return a, nil
}

// toggleFavorite toggles favorite status for selected port
func (a *App) toggleFavorite() (tea.Model, tea.Cmd) {
	if len(a.filtered) == 0 || a.cursor >= len(a.filtered) {
		return a, nil
	}

	item := a.filtered[a.cursor]
	if a.config == nil {
		a.config = &config.Config{}
	}

	if item.IsFavorite {
		a.config.RemoveFavorite(item.Port.Port)
		a.setStatus(fmt.Sprintf("Removed port %d from favorites", item.Port.Port), false)
	} else {
		a.config.AddFavorite(item.Port.Port)
		a.setStatus(fmt.Sprintf("Added port %d to favorites", item.Port.Port), false)
	}

	a.configStore.Save(a.config)
	a.updateFilteredPorts()
	return a, nil
}

// toggleWatch toggles watch status for selected port
func (a *App) toggleWatch() (tea.Model, tea.Cmd) {
	if len(a.filtered) == 0 || a.cursor >= len(a.filtered) {
		return a, nil
	}

	item := a.filtered[a.cursor]
	if a.config == nil {
		a.config = &config.Config{}
	}

	if item.IsWatched {
		a.config.RemoveWatched(item.Port.Port)
		a.setStatus(fmt.Sprintf("Stopped watching port %d", item.Port.Port), false)
	} else {
		a.config.AddWatched(item.Port.Port)
		a.setStatus(fmt.Sprintf("Now watching port %d", item.Port.Port), false)
	}

	a.configStore.Save(a.config)
	a.updateFilteredPorts()
	return a, nil
}

// detectProcessType guesses the process type from its name
func detectProcessType(process string) string {
	p := strings.ToLower(process)

	// Web servers
	webServers := []string{"nginx", "apache", "httpd", "node", "deno", "bun", "python", "ruby", "php", "caddy", "traefik"}
	for _, ws := range webServers {
		if strings.Contains(p, ws) {
			return "WebServer"
		}
	}

	// Databases
	databases := []string{"mysql", "postgres", "mongo", "redis", "sqlite", "mariadb", "cockroach", "elastic", "clickhouse"}
	for _, db := range databases {
		if strings.Contains(p, db) {
			return "Database"
		}
	}

	// Development tools
	devTools := []string{"vite", "webpack", "esbuild", "tsc", "go", "cargo", "npm", "yarn", "pnpm", "turbo", "nx"}
	for _, dt := range devTools {
		if strings.Contains(p, dt) {
			return "Development"
		}
	}

	// System
	systemProcs := []string{"launchd", "kernel", "systemd", "init", "cron", "sshd"}
	for _, sp := range systemProcs {
		if strings.Contains(p, sp) {
			return "System"
		}
	}

	return "Other"
}
