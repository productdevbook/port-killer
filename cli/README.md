# portkiller

A fast, cross-platform CLI tool to find and kill processes listening on ports.

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

### List all listening ports

```bash
portkiller
# or
portkiller list
```

Output:
```
PORT   PID    PROCESS       USER  ADDRESS
----   ---    -------       ----  -------
3000   1234   node          user  127.0.0.1
5432   5678   postgres      user  *
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

## Platform Support

| Platform | Status |
|----------|--------|
| macOS (Apple Silicon) | ✅ |
| macOS (Intel) | ✅ |
| Linux (x64) | ✅ |
| Linux (ARM64) | ✅ |
| Windows (x64) | ✅ |

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

## Related

- [PortKiller GUI](https://github.com/productdevbook/port-killer) - macOS menu bar app with the same functionality

## License

MIT
