package cmd

import (
	"fmt"
	"strconv"

	"github.com/charmbracelet/lipgloss"
	"github.com/productdevbook/port-killer/cli/internal/config"
	"github.com/spf13/cobra"
)

var watchCmd = &cobra.Command{
	Use:   "watch",
	Short: "Manage watched ports",
	Long:  `List, add, or remove watched ports. Syncs with PortKiller GUI on macOS.`,
	RunE:  runWatchList,
}

var watchAddCmd = &cobra.Command{
	Use:   "add <port>",
	Short: "Add a port to watch list",
	Args:  cobra.ExactArgs(1),
	RunE:  runWatchAdd,
}

var watchRemoveCmd = &cobra.Command{
	Use:   "remove <port>",
	Short: "Remove a port from watch list",
	Args:  cobra.ExactArgs(1),
	RunE:  runWatchRemove,
}

func init() {
	watchCmd.AddCommand(watchAddCmd)
	watchCmd.AddCommand(watchRemoveCmd)
	rootCmd.AddCommand(watchCmd)
}

func runWatchList(cmd *cobra.Command, args []string) error {
	store := config.NewStore()
	cfg, err := store.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if len(cfg.WatchedPorts) == 0 {
		fmt.Println(dimStyle.Render("No watched ports."))
		fmt.Println(dimStyle.Render("Add one with: portkiller watch add <port>"))
		return nil
	}

	fmt.Println(headerStyle.Render("Watched Ports"))
	fmt.Println(dimStyle.Render("─────────────"))

	for _, wp := range cfg.WatchedPorts {
		notifications := ""
		if wp.NotifyOnStart {
			notifications += "start"
		}
		if wp.NotifyOnStop {
			if notifications != "" {
				notifications += ", "
			}
			notifications += "stop"
		}
		line := fmt.Sprintf("👁 %d", wp.Port)
		if notifications != "" {
			line += dimStyle.Render(fmt.Sprintf(" (notify: %s)", notifications))
		}
		fmt.Println(watchedStyle.Render(line))
	}

	return nil
}

func runWatchAdd(cmd *cobra.Command, args []string) error {
	port, err := strconv.Atoi(args[0])
	if err != nil {
		return fmt.Errorf("invalid port number: %s", args[0])
	}

	store := config.NewStore()
	cfg, err := store.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if cfg.IsWatched(port) {
		fmt.Println(dimStyle.Render(fmt.Sprintf("Port %d is already being watched.", port)))
		return nil
	}

	cfg.AddWatched(port)

	if err := store.Save(cfg); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("82"))
	fmt.Println(successStyle.Render(fmt.Sprintf("✓ Now watching port %d", port)))

	return nil
}

func runWatchRemove(cmd *cobra.Command, args []string) error {
	port, err := strconv.Atoi(args[0])
	if err != nil {
		return fmt.Errorf("invalid port number: %s", args[0])
	}

	store := config.NewStore()
	cfg, err := store.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if !cfg.IsWatched(port) {
		fmt.Println(dimStyle.Render(fmt.Sprintf("Port %d is not being watched.", port)))
		return nil
	}

	cfg.RemoveWatched(port)

	if err := store.Save(cfg); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	fmt.Println(dimStyle.Render(fmt.Sprintf("✓ Stopped watching port %d", port)))

	return nil
}
