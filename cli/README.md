# portkiller

A fast, cross-platform CLI tool to find and kill processes listening on ports.

## Installation

### From Source

```bash
go install github.com/productdevbook/port-killer/cli@latest
```

### From Releases

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
| macOS    | ✅     |
| Linux    | ✅     |
| Windows  | ✅     |

## Building

```bash
# Build for current platform
go build -o portkiller .

# Cross-compile
GOOS=linux GOARCH=amd64 go build -o portkiller-linux .
GOOS=windows GOARCH=amd64 go build -o portkiller.exe .
GOOS=darwin GOARCH=arm64 go build -o portkiller-mac .
```

## License

MIT
