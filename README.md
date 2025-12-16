# PortKiller

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-15.0%2B-brightgreen)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![GitHub Release](https://img.shields.io/github/v/release/productdevbook/port-killer)](https://github.com/productdevbook/port-killer/releases)

A native macOS menu bar application for finding and killing processes running on open ports. Perfect for developers who need to quickly free up ports like 3000, 8080, 5173, etc.

<p align="center">
  <img src=".github/assets/port-kill.gif" alt="PortKiller Demo" width="400">
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

### Download (Recommended)

Download the latest DMG from [GitHub Releases](https://github.com/productdevbook/port-killer/releases):

1. Download `PortKiller-vX.X.X.dmg`
2. Open the DMG file
3. Drag PortKiller to your Applications folder
4. Launch from Applications or Spotlight

### macOS Security Notice

Since PortKiller is not signed with an Apple Developer certificate, macOS will show a security warning on first launch. Here's how to open it:

**Method 1: Right-Click (Easiest)**
1. Right-click (or Control-click) on PortKiller in Applications
2. Select "Open" from the context menu
3. Click "Open" in the dialog that appears

**Method 2: System Settings**
1. Try to open PortKiller normally (it will be blocked)
2. Open **System Settings** → **Privacy & Security**
3. Scroll down to find the message about PortKiller being blocked
4. Click **"Open Anyway"**
5. Enter your password if prompted
6. Launch PortKiller again

**Method 3: Terminal**
```bash
xattr -d com.apple.quarantine /Applications/PortKiller.app
```

> ⚠️ **Note**: This is a one-time setup. After allowing it once, PortKiller will open normally.

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

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
