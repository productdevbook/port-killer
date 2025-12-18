package cmd

import (
	"github.com/spf13/cobra"
)

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "List all listening ports",
	Long:  `List all TCP ports currently in LISTEN state with their associated processes.`,
	RunE:  runList,
}
