package cmd

import (
	"fmt"
	"strconv"

	"github.com/productdevbook/port-killer/cli/internal/scanner"
	"github.com/spf13/cobra"
)

var forceKill bool

var killCmd = &cobra.Command{
	Use:   "kill <port>",
	Short: "Kill process listening on a port",
	Long:  `Kill the process that is listening on the specified port. Uses SIGTERM by default, SIGKILL with --force.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runKill,
}

func init() {
	killCmd.Flags().BoolVarP(&forceKill, "force", "f", false, "Force kill with SIGKILL")
}

func runKill(cmd *cobra.Command, args []string) error {
	port, err := strconv.Atoi(args[0])
	if err != nil {
		return fmt.Errorf("invalid port number: %s", args[0])
	}

	s := scanner.New()
	ports, err := s.Scan()
	if err != nil {
		return fmt.Errorf("failed to scan ports: %w", err)
	}

	// Find the process on this port
	var target *scanner.Port
	for _, p := range ports {
		if p.Port == port {
			target = &p
			break
		}
	}

	if target == nil {
		return fmt.Errorf("no process found listening on port %d", port)
	}

	// Kill the process
	if err := s.Kill(target.PID, forceKill); err != nil {
		return fmt.Errorf("failed to kill process %d: %w", target.PID, err)
	}

	action := "Killed"
	if forceKill {
		action = "Force killed"
	}
	fmt.Printf("%s %s (PID %d) on port %d\n", action, target.Process, target.PID, target.Port)

	return nil
}
