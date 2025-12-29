package cmd

import (
	"fmt"
	"strconv"

	"github.com/charmbracelet/lipgloss"
	"github.com/productdevbook/port-killer/cli/internal/config"
	"github.com/spf13/cobra"
)

var favoritesCmd = &cobra.Command{
	Use:   "favorites",
	Short: "Manage favorite ports",
	Long:  `List, add, or remove favorite ports. Syncs with PortKiller GUI on macOS.`,
	RunE:  runFavoritesList,
}

var favoritesAddCmd = &cobra.Command{
	Use:   "add <port>",
	Short: "Add a port to favorites",
	Args:  cobra.ExactArgs(1),
	RunE:  runFavoritesAdd,
}

var favoritesRemoveCmd = &cobra.Command{
	Use:   "remove <port>",
	Short: "Remove a port from favorites",
	Args:  cobra.ExactArgs(1),
	RunE:  runFavoritesRemove,
}

func init() {
	favoritesCmd.AddCommand(favoritesAddCmd)
	favoritesCmd.AddCommand(favoritesRemoveCmd)
	rootCmd.AddCommand(favoritesCmd)
}

func runFavoritesList(cmd *cobra.Command, args []string) error {
	store := config.NewStore()
	cfg, err := store.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if len(cfg.Favorites) == 0 {
		fmt.Println(dimStyle.Render("No favorite ports."))
		fmt.Println(dimStyle.Render("Add one with: portkiller favorites add <port>"))
		return nil
	}

	fmt.Println(headerStyle.Render("Favorite Ports"))
	fmt.Println(dimStyle.Render("──────────────"))

	for _, port := range cfg.Favorites {
		fmt.Println(favoriteStyle.Render(fmt.Sprintf("⭐ %d", port)))
	}

	return nil
}

func runFavoritesAdd(cmd *cobra.Command, args []string) error {
	port, err := strconv.Atoi(args[0])
	if err != nil {
		return fmt.Errorf("invalid port number: %s", args[0])
	}

	store := config.NewStore()
	cfg, err := store.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if cfg.IsFavorite(port) {
		fmt.Println(dimStyle.Render(fmt.Sprintf("Port %d is already a favorite.", port)))
		return nil
	}

	cfg.AddFavorite(port)

	if err := store.Save(cfg); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	successStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("82"))
	fmt.Println(successStyle.Render(fmt.Sprintf("✓ Added port %d to favorites", port)))

	return nil
}

func runFavoritesRemove(cmd *cobra.Command, args []string) error {
	port, err := strconv.Atoi(args[0])
	if err != nil {
		return fmt.Errorf("invalid port number: %s", args[0])
	}

	store := config.NewStore()
	cfg, err := store.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if !cfg.IsFavorite(port) {
		fmt.Println(dimStyle.Render(fmt.Sprintf("Port %d is not a favorite.", port)))
		return nil
	}

	cfg.RemoveFavorite(port)

	if err := store.Save(cfg); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	fmt.Println(dimStyle.Render(fmt.Sprintf("✓ Removed port %d from favorites", port)))

	return nil
}
