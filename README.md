# PortKiller

<p align="center">
  <img src="Resources/AppIcon.svg" alt="PortKiller Icon" width="128" height="128">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15.0%2B-brightgreen" alt="macOS"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.2-orange" alt="Swift"></a>
  <a href="https://github.com/productdevbook/port-killer/releases"><img src="https://img.shields.io/github/v/release/productdevbook/port-killer" alt="GitHub Release"></a>
</p>

<p align="center">
A native macOS menu bar app for finding and killing processes on open ports.<br>
Perfect for developers who need to quickly free up ports like 3000, 8080, 5173, etc.
</p>

<p align="center">
  <img src=".github/assets/image.jpeg" alt="PortKiller Demo" width="full">
</p>

## Installation

### macOS App (Homebrew)

```bash
brew install --cask productdevbook/tap/portkiller
```

### CLI Tool (Homebrew)

```bash
brew install productdevbook/tap/portkiller
```

### Download

Download from [GitHub Releases](https://github.com/productdevbook/port-killer/releases).

## CLI Usage

```bash
# List all listening ports
portkiller

# Interactive TUI mode
portkiller tui
# or
portkiller -i

# Kill process on specific port
portkiller kill 3000

# Force kill
portkiller kill 3000 -f
```

### TUI Keybindings

| Key | Action |
|-----|--------|
| `j/k` | Navigate up/down |
| `x` | Kill process |
| `X` | Force kill |
| `space` | Select multiple |
| `f` | Toggle favorite |
| `w` | Toggle watch |
| `/` | Command palette |
| `?` | Help |
| `q` | Quit |

## How It Works

```mermaid
flowchart TD
    subgraph Interface
        A[macOS Menu Bar]
        B[CLI Command]
        C[TUI Interactive]
    end

    A --> PS[Port Scanner]
    B --> PS
    C --> PS

    PS --> LSOF[lsof -iTCP -P]
    PS --> PSINFO[ps process info]

    LSOF --> PARSE[Parse Output]
    PSINFO --> PARSE

    CONFIG[(~/.portkiller/config.json)] --> |Favorites, Watched| DATA
    PARSE --> DATA[Port List]

    DATA --> F[Display Ports]
    DATA --> G[Kill Process]
    DATA --> H[Watch & Notify]

    G --> I[kill -15 SIGTERM]
    I --> J[kill -9 SIGKILL]
```

## Features

- 📍 Menu bar integration
- 🔍 Auto-discovers listening TCP ports
- ⚡ One-click process termination
- 🔄 Auto-refresh every 5 seconds
- 🔎 Search by port or process name

## Platform Support

| Platform | Status |
|----------|--------|
| macOS | Supported |
| Linux | In Progress |
| Windows | In Progress |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup.

## Sponsors

<p align="center">
  <a href="https://cdn.jsdelivr.net/gh/productdevbook/static/sponsors.svg">
    <img src='https://cdn.jsdelivr.net/gh/productdevbook/static/sponsors.svg'/>
  </a>
</p>

## License

MIT License - see [LICENSE](LICENSE).
