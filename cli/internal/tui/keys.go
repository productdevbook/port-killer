package tui

import "github.com/charmbracelet/bubbles/key"

// KeyMap defines all keybindings for the TUI
type KeyMap struct {
	// Navigation
	Up       key.Binding
	Down     key.Binding
	PageUp   key.Binding
	PageDown key.Binding
	Home     key.Binding
	End      key.Binding

	// Actions
	Kill      key.Binding
	ForceKill key.Binding
	Favorite  key.Binding
	Watch     key.Binding
	Refresh   key.Binding

	// Selection
	Select    key.Binding
	SelectAll key.Binding

	// Modes
	Search key.Binding
	Help   key.Binding
	Detail key.Binding
	Logs   key.Binding
	Copy   key.Binding
	Export key.Binding

	// General
	Enter  key.Binding
	Escape key.Binding
	Quit   key.Binding

	// Grouping
	GroupByType key.Binding
	SortByPort  key.Binding
	SortByName  key.Binding
}

// DefaultKeyMap returns the default keybindings
func DefaultKeyMap() KeyMap {
	return KeyMap{
		Up: key.NewBinding(
			key.WithKeys("up", "k"),
			key.WithHelp("↑/k", "up"),
		),
		Down: key.NewBinding(
			key.WithKeys("down", "j"),
			key.WithHelp("↓/j", "down"),
		),
		PageUp: key.NewBinding(
			key.WithKeys("pgup", "ctrl+u"),
			key.WithHelp("pgup", "page up"),
		),
		PageDown: key.NewBinding(
			key.WithKeys("pgdown", "ctrl+d"),
			key.WithHelp("pgdn", "page down"),
		),
		Home: key.NewBinding(
			key.WithKeys("home", "g"),
			key.WithHelp("g", "top"),
		),
		End: key.NewBinding(
			key.WithKeys("end", "G"),
			key.WithHelp("G", "bottom"),
		),
		Kill: key.NewBinding(
			key.WithKeys("x", "delete", "backspace"),
			key.WithHelp("x", "kill"),
		),
		ForceKill: key.NewBinding(
			key.WithKeys("X"),
			key.WithHelp("X", "force kill"),
		),
		Favorite: key.NewBinding(
			key.WithKeys("f"),
			key.WithHelp("f", "favorite"),
		),
		Watch: key.NewBinding(
			key.WithKeys("w"),
			key.WithHelp("w", "watch"),
		),
		Refresh: key.NewBinding(
			key.WithKeys("r"),
			key.WithHelp("r", "refresh"),
		),
		Select: key.NewBinding(
			key.WithKeys(" "),
			key.WithHelp("space", "select"),
		),
		SelectAll: key.NewBinding(
			key.WithKeys("ctrl+a"),
			key.WithHelp("ctrl+a", "select all"),
		),
		Search: key.NewBinding(
			key.WithKeys("/"),
			key.WithHelp("/", "commands"),
		),
		Help: key.NewBinding(
			key.WithKeys("?"),
			key.WithHelp("?", "help"),
		),
		Detail: key.NewBinding(
			key.WithKeys("enter", "l"),
			key.WithHelp("↵/l", "details"),
		),
		Logs: key.NewBinding(
			key.WithKeys("L"),
			key.WithHelp("L", "logs"),
		),
		Copy: key.NewBinding(
			key.WithKeys("c"),
			key.WithHelp("c", "copy"),
		),
		Export: key.NewBinding(
			key.WithKeys("e"),
			key.WithHelp("e", "export"),
		),
		Enter: key.NewBinding(
			key.WithKeys("enter"),
			key.WithHelp("↵", "select"),
		),
		Escape: key.NewBinding(
			key.WithKeys("esc"),
			key.WithHelp("esc", "back"),
		),
		Quit: key.NewBinding(
			key.WithKeys("q", "ctrl+c"),
			key.WithHelp("q", "quit"),
		),
		GroupByType: key.NewBinding(
			key.WithKeys("t"),
			key.WithHelp("t", "group by type"),
		),
		SortByPort: key.NewBinding(
			key.WithKeys("1"),
			key.WithHelp("1", "sort by port"),
		),
		SortByName: key.NewBinding(
			key.WithKeys("2"),
			key.WithHelp("2", "sort by name"),
		),
	}
}

// ShortHelp returns a minimal set of keybindings for the help bar
func (k KeyMap) ShortHelp() []key.Binding {
	return []key.Binding{
		k.Up, k.Down, k.Kill, k.Favorite, k.Watch, k.Search, k.Help, k.Quit,
	}
}

// FullHelp returns all keybindings organized in groups
func (k KeyMap) FullHelp() [][]key.Binding {
	return [][]key.Binding{
		{k.Up, k.Down, k.PageUp, k.PageDown, k.Home, k.End},
		{k.Kill, k.ForceKill, k.Favorite, k.Watch},
		{k.Search, k.Refresh, k.Detail},
		{k.GroupByType, k.SortByPort, k.SortByName},
		{k.Help, k.Quit},
	}
}
