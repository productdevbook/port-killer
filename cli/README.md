# portkiller

A fast, cross-platform CLI tool to find and kill processes listening on ports. Features an interactive TUI (Terminal User Interface) with real-time updates, vim-style navigation, and fuzzy search.

![portkiller TUI](https://raw.githubusercontent.com/productdevbook/port-killer/main/cli/assets/tui-preview.png)

## Features

- **Interactive TUI** - Full-screen interface with real-time port monitoring
- **Vim-style navigation** - `j/k` to move, `g/G` for top/bottom
- **Fuzzy search** - Press `/` to instantly filter ports
- **Quick actions** - `x` to kill, `f` to favorite, `w` to watch
- **Process categorization** - Color-coded by type (WebServer, Database, Dev Tools, etc.)
- **Favorites & Watch lists** - Syncs with PortKiller GUI on macOS
- **Kill confirmation** - Safe deletion with confirmation dialog
- **Auto-refresh** - Ports update every 5 seconds
- **Scriptable** - Use `--no-tui` or `--json` for automation

## Installation

### Homebrew (macOS/Linux)

```bash
brew tap productdevbook/tap
brew install portkiller-cli
```

### Quick Install (macOS/Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/productdevbook/port-killer/main/cli/install.sh | sh
```

### Go Install

```bash
go install github.com/productdevbook/port-killer/cli@latest
```

### Manual Download

Download the binary for your platform from [Releases](https://github.com/productdevbook/port-killer/releases).

## Usage

### Interactive TUI (default)

Simply run `portkiller` to launch the interactive interface:

```bash
portkiller
```

#### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `g` | Go to top |
| `G` | Go to bottom |
| `x` / `Del` | Kill process (with confirmation) |
| `X` | Force kill (SIGKILL) |
| `f` | Toggle favorite |
| `w` | Toggle watch |
| `/` | Search / filter |
| `Enter` / `l` | View details |
| `r` | Refresh |
| `1` | Sort by port |
| `2` | Sort by name |
| `?` | Show help |
| `q` | Quit |

### Traditional CLI Mode

For scripts or piping, use `--no-tui`:

```bash
portkiller --no-tui
# or
portkiller list
```

Output:
```
PORT   PID    PROCESS       USER  ADDRESS    STATUS
─────────────────────────────────────────────────────
3000   1234   node          user  127.0.0.1  ⭐
5432   5678   postgres      user  *          👁
8080   9012   java          user  0.0.0.0
```

### JSON output

```bash
portkiller --json
```

### Kill a process

```bash
# Graceful kill (SIGTERM, then SIGKILL after 500ms if needed)
portkiller kill 3000

# Force kill (SIGKILL immediately)
portkiller kill 3000 --force
```

### Favorites & Watch

```bash
# List favorites
portkiller favorites

# Add/remove favorite
portkiller favorites add 3000
portkiller favorites remove 3000

# List watched ports
portkiller watch

# Add/remove watched port
portkiller watch add 3000
portkiller watch remove 3000
```

> **Note:** Favorites and watched ports sync with PortKiller GUI on macOS.

## Platform Support

| Platform | Status |
|----------|--------|
| macOS (Apple Silicon) | ✅ |
| macOS (Intel) | ✅ |
| Linux (x64) | ✅ |
| Linux (ARM64) | ✅ |
| Windows (x64) | ✅ |

## Shell Completion

```bash
# Zsh (add to ~/.zshrc)
source <(portkiller completion zsh)

# Bash (add to ~/.bashrc)
source <(portkiller completion bash)

# Fish
portkiller completion fish | source

# PowerShell
portkiller completion powershell | Out-String | Invoke-Expression
```

## Building from Source

```bash
cd cli

# Build for current platform
go build -o portkiller .

# Cross-compile
GOOS=linux GOARCH=amd64 go build -o portkiller-linux-amd64 .
GOOS=linux GOARCH=arm64 go build -o portkiller-linux-arm64 .
GOOS=darwin GOARCH=amd64 go build -o portkiller-darwin-amd64 .
GOOS=darwin GOARCH=arm64 go build -o portkiller-darwin-arm64 .
GOOS=windows GOARCH=amd64 go build -o portkiller-windows-amd64.exe .
```

## Development

### Prerequisites

- Go 1.21+

### Setup

```bash
cd cli
go mod download
```

### Run locally

```bash
go run .
go run . --json
go run . kill 3000
```

### Install locally

```bash
go build -o ~/.go/bin/portkiller .
# or
go build -o /usr/local/bin/portkiller .
```

### Project structure

```
cli/
├── main.go                 # Entry point
├── cmd/
│   ├── root.go             # Root command (TUI or list)
│   ├── list.go             # List subcommand
│   ├── kill.go             # Kill subcommand
│   ├── favorites.go        # Favorites management
│   └── watch.go            # Watch list management
└── internal/
    ├── config/
    │   ├── config.go       # Config types & helpers
    │   ├── darwin.go       # macOS plist storage
    │   └── other.go        # Linux/Windows JSON storage
    ├── scanner/
    │   ├── scanner.go      # Scanner interface
    │   ├── darwin.go       # macOS (lsof)
    │   ├── linux.go        # Linux (lsof/ss)
    │   └── windows.go      # Windows (netstat)
    └── tui/
        ├── tui.go          # Interactive TUI (Bubble Tea)
        ├── styles.go       # macOS-inspired styling
        └── keys.go         # Keyboard bindings
```

### Adding a new command

```go
// cmd/mycommand.go
package cmd

import "github.com/spf13/cobra"

var myCmd = &cobra.Command{
    Use:   "mycommand",
    Short: "Description",
    RunE: func(cmd *cobra.Command, args []string) error {
        // implementation
        return nil
    },
}

func init() {
    rootCmd.AddCommand(myCmd)
}
```

### Release

```bash
pnpm release:cli
```

## Related

- [PortKiller GUI](https://github.com/productdevbook/port-killer) - macOS menu bar app with the same functionality

## License

MIT
