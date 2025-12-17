# PortKiller

<p align="center">
  <img src="Resources/AppIcon.svg" alt="PortKiller Icon" width="128" height="128">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15.0%2B-brightgreen" alt="macOS"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift"></a>
  <a href="https://github.com/productdevbook/port-killer/releases"><img src="https://img.shields.io/github/v/release/productdevbook/port-killer" alt="GitHub Release"></a>
</p>

<p align="center">
A native macOS menu bar application for finding and killing processes running on open ports.<br>
Perfect for developers who need to quickly free up ports like 3000, 8080, 5173, etc.
</p>

<p align="center">
  <img src=".github/assets/image.jpeg" alt="PortKiller Demo" width="400">
</p>

## Features

- **Menu Bar Integration** - Lives in your menu bar, no Dock icon clutter
- **Port Discovery** - Automatically finds all listening TCP ports
- **Process Info** - Shows process name and PID for each port
- **📋 Process Descriptions** - Intelligent descriptions for any process (Node.js, nginx, MySQL, etc.)
- **🔍 Expandable Details** - Click info icons to see full process descriptions
- **🎨 Visual Categories** - Color-coded icons for different process types (dev tools, databases, web servers, system services)
- **Quick Kill** - One-click process termination
- **Kill All** - Terminate all listed processes at once
- **Auto-Refresh** - Updates port list every 5 seconds
- **Search** - Filter by port number or process name
- **Graceful Kill** - Tries SIGTERM first, then SIGKILL if needed

## Requirements

- macOS 15.0+ (Sequoia)

## Installation

### Homebrew (Recommended)

```bash
brew install --cask productdevbook/tap/portkiller
```

### Download

Download the latest DMG from [GitHub Releases](https://github.com/productdevbook/port-killer/releases):

1. Download `PortKiller-vX.X.X-arm64.dmg`
2. Open the DMG file
3. Drag PortKiller to your Applications folder
4. Launch from Applications or Spotlight

### Build from Source

```bash
# Clone the repository
git clone https://github.com/productdevbook/port-killer.git
cd port-killer

# Build the app bundle
./scripts/build-app.sh

# Copy to Applications
cp -r .build/release/PortKiller.app /Applications/

# Launch
open /Applications/PortKiller.app
```

## Usage

1. Click the network icon in the menu bar
2. See all open ports with their process names and descriptions
3. Click the blue ℹ️ icon next to processes to expand full descriptions
4. Use color-coded category icons to quickly identify process types:
   - 🔨 **Blue** = Development tools (webpack, nodemon, rails)
   - 🗄️ **Green** = Database services (MySQL, PostgreSQL, Redis)
   - 🌐 **Orange** = Web servers (nginx, Apache, Node.js servers)
   - ⚙️ **Purple** = System services (Docker, launchd, system daemons)
   - 📱 **Gray** = Other applications
5. Click the ✕ button to kill a specific process
6. Use "Kill All" to terminate all listed processes
7. Search by port number or process name

## How It Works

PortKiller uses `lsof` to find all processes listening on TCP ports:

```bash
lsof -iTCP -sTCP:LISTEN -P -n
```

When you kill a process, it first tries a graceful termination (SIGTERM), then forces it (SIGKILL) if needed.

## Development

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run directly
swift run PortKiller

# Open in Xcode
open Package.swift
```

### Project Structure

```
Sources/
├── PortKillerApp.swift              # App entry point
├── AppState.swift                   # State management
├── PortScanner.swift                # Port scanning (lsof)
├── ProcessDescriptionService.swift  # Process description intelligence
├── Models/
│   └── Models.swift                 # Data models (PortInfo, ProcessDescription)
└── Views/
    ├── MenuBarView.swift            # Main UI with expandable descriptions
    └── SettingsView.swift           # Settings interface
Resources/
└── descriptions.json                # Process description database
Tests/
├── ProcessDescriptionServiceTests.swift  # Comprehensive test suite
└── IntegrationTests.swift               # End-to-end tests
```

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a Pull Request.

## Sponsors

<p align="center">
  <a href="https://cdn.jsdelivr.net/gh/productdevbook/static/sponsors.svg">
    <img src='https://cdn.jsdelivr.net/gh/productdevbook/static/sponsors.svg'/>
  </a>
</p>


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
