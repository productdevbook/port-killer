package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/mattn/go-isatty"
	"github.com/productdevbook/port-killer/cli/internal/config"
	"github.com/productdevbook/port-killer/cli/internal/scanner"
	"github.com/productdevbook/port-killer/cli/internal/tui"
	"github.com/spf13/cobra"
)

var (
	version    = "0.1.0"
	jsonOutput bool
	noTUI      bool
)

// Styles
var (
	headerStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("99"))

	favoriteStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("220")) // Yellow

	watchedStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("86")) // Cyan

	bothStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("82")). // Green
			Bold(true)

	dimStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("240"))
)

var rootCmd = &cobra.Command{
	Use:   "portkiller",
	Short: "A fast port killer for developers",
	Long:  `portkiller is a cross-platform CLI tool to list and kill processes listening on ports.`,
	RunE:  runList,
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().BoolVar(&jsonOutput, "json", false, "Output in JSON format")
	rootCmd.PersistentFlags().BoolVar(&noTUI, "no-tui", false, "Disable interactive TUI mode")
	rootCmd.AddCommand(listCmd)
	rootCmd.AddCommand(killCmd)
	rootCmd.Version = version
}

func runList(cmd *cobra.Command, args []string) error {
	// Check if we should use TUI
	// Use TUI if: interactive terminal, not piped, not JSON output, not --no-tui
	isInteractive := isatty.IsTerminal(os.Stdout.Fd()) || isatty.IsCygwinTerminal(os.Stdout.Fd())

	if isInteractive && !jsonOutput && !noTUI {
		return tui.Run()
	}

	// Traditional CLI mode
	s := scanner.New()
	ports, err := s.Scan()
	if err != nil {
		return fmt.Errorf("failed to scan ports: %w", err)
	}

	if len(ports) == 0 {
		if jsonOutput {
			fmt.Println("[]")
		} else {
			fmt.Println(dimStyle.Render("No listening ports found."))
		}
		return nil
	}

	// Load config for favorites/watched
	store := config.NewStore()
	cfg, _ := store.Load()
	if cfg == nil {
		cfg = &config.Config{}
	}

	// Sort: favorites first, then by port number
	sort.Slice(ports, func(i, j int) bool {
		iFav := cfg.IsFavorite(ports[i].Port)
		jFav := cfg.IsFavorite(ports[j].Port)
		if iFav != jFav {
			return iFav
		}
		return ports[i].Port < ports[j].Port
	})

	if jsonOutput {
		return printJSON(ports)
	}

	return printTable(ports, cfg)
}

func printJSON(ports []scanner.Port) error {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(ports)
}

func printTable(ports []scanner.Port, cfg *config.Config) error {
	// Calculate column widths
	maxPort := 4
	maxPID := 3
	maxProcess := 7
	maxUser := 4
	maxAddr := 7

	for _, p := range ports {
		if l := len(fmt.Sprintf("%d", p.Port)); l > maxPort {
			maxPort = l
		}
		if l := len(fmt.Sprintf("%d", p.PID)); l > maxPID {
			maxPID = l
		}
		if l := len(p.Process); l > maxProcess {
			maxProcess = l
		}
		if l := len(p.User); l > maxUser {
			maxUser = l
		}
		if l := len(p.Address); l > maxAddr {
			maxAddr = l
		}
	}

	// Print header
	header := fmt.Sprintf("%-*s  %-*s  %-*s  %-*s  %-*s  %s",
		maxPort, "PORT",
		maxPID, "PID",
		maxProcess, "PROCESS",
		maxUser, "USER",
		maxAddr, "ADDRESS",
		"STATUS")
	fmt.Println(headerStyle.Render(header))
	fmt.Println(dimStyle.Render(strings.Repeat("─", len(header)+2)))

	// Print rows
	for _, p := range ports {
		user := p.User
		if user == "" {
			user = "-"
		}

		// Determine status icons and style
		isFav := cfg.IsFavorite(p.Port)
		isWatch := cfg.IsWatched(p.Port)

		var status string
		var style lipgloss.Style

		switch {
		case isFav && isWatch:
			status = "⭐👁"
			style = bothStyle
		case isFav:
			status = "⭐"
			style = favoriteStyle
		case isWatch:
			status = "👁"
			style = watchedStyle
		default:
			status = ""
			style = lipgloss.NewStyle()
		}

		row := fmt.Sprintf("%-*d  %-*d  %-*s  %-*s  %-*s  %s",
			maxPort, p.Port,
			maxPID, p.PID,
			maxProcess, p.Process,
			maxUser, user,
			maxAddr, p.Address,
			status)

		fmt.Println(style.Render(row))
	}

	return nil
}
