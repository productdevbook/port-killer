package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"text/tabwriter"

	"github.com/productdevbook/port-killer/cli/internal/scanner"
	"github.com/spf13/cobra"
)

var (
	version   = "0.1.0"
	jsonOutput bool
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
	rootCmd.AddCommand(listCmd)
	rootCmd.AddCommand(killCmd)
	rootCmd.Version = version
}

func runList(cmd *cobra.Command, args []string) error {
	s := scanner.New()
	ports, err := s.Scan()
	if err != nil {
		return fmt.Errorf("failed to scan ports: %w", err)
	}

	if len(ports) == 0 {
		if jsonOutput {
			fmt.Println("[]")
		} else {
			fmt.Println("No listening ports found.")
		}
		return nil
	}

	// Sort by port number
	sort.Slice(ports, func(i, j int) bool {
		return ports[i].Port < ports[j].Port
	})

	if jsonOutput {
		return printJSON(ports)
	}

	return printTable(ports)
}

func printJSON(ports []scanner.Port) error {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(ports)
}

func printTable(ports []scanner.Port) error {
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(w, "PORT\tPID\tPROCESS\tUSER\tADDRESS")
	fmt.Fprintln(w, "----\t---\t-------\t----\t-------")

	for _, p := range ports {
		user := p.User
		if user == "" {
			user = "-"
		}
		fmt.Fprintf(w, "%d\t%d\t%s\t%s\t%s\n", p.Port, p.PID, p.Process, user, p.Address)
	}

	return w.Flush()
}
