# Contributing

## Requirements

- **macOS 15.0+** / **Windows 10+** / **Linux**
- **Xcode 16+** with Swift 6.0 (for macOS)
- **.NET 9 SDK** (for Windows)
- **Python 3.9+**, PyGObject (GTK 3) and libayatana-appindicator (for Linux)
- **Rust stable** (for `portkiller-core`, used by the Linux app only)

## Setup

```bash
git clone https://github.com/productdevbook/port-killer.git
cd port-killer
```

## Running the App

### macOS

```bash
cd platforms/macos

# Option 1: Xcode (recommended)
open Package.swift
# Press ▶️ to run

# Option 2: Build script
./scripts/build-app.sh && open .build/apple/Products/Release/PortKiller.app
```

> ⚠️ `swift run` doesn't work for menu bar apps - use Xcode or the build script.

### Windows

```bash
cd platforms/windows/PortKiller
dotnet run
```

### Linux

A native system tray app built with Python, GTK 3 and AppIndicator.

```bash
# Run directly
./platforms/linux/port-killer.py &

# Or install it (registers a launcher and autostart on login)
./platforms/linux/install.sh
```

Install the dependencies first — `install.sh` checks for them and stops with
hints if any are missing:

```bash
# Debian/Ubuntu
sudo apt install python3 python3-gi gir1.2-ayatanaappindicator3-0.1

# Fedora
sudo dnf install python3 python3-gobject libayatana-appindicator-gtk3

# Arch
sudo pacman -S python python-gobject libayatana-appindicator
```

## Building

### macOS

```bash
cd platforms/macos
swift build              # Debug
swift build -c release   # Release
./scripts/build-app.sh   # App bundle
```

### Windows

```bash
cd platforms/windows/PortKiller
dotnet build             # Debug
dotnet publish -c Release -r win-x64  # Release
```

### Linux

The tray app is plain Python, so there is no build step. The Rust core is
built separately:

```bash
cd portkiller-core
cargo build              # Debug
cargo build --release    # Release
```

Releases ship an AppImage, produced by the `build-linux` job in
`.github/workflows/release.yml`.

## Tests

```bash
# macOS
cd platforms/macos && swift test

# Linux tray app (parser tests, no GTK needed)
python3 -m unittest discover -s platforms/linux/tests

# Rust core (Linux only)
cd portkiller-core && cargo test
```

## Pull Requests

1. Fork the repo
2. Create a branch (`git checkout -b feature/my-feature`)
3. Make changes and test locally
4. Commit (`git commit -m "feat: add feature"`)
5. Push and create PR

## Code Style

### macOS
- Swift 6.0 with strict concurrency
- SwiftUI for UI
- `@Observable` for state management
- Keep files under 300 lines

### Windows
- C# with WPF
- MVVM pattern

### Linux
- Python 3 with GTK 3 (PyGObject)
- Scans run on a worker thread; UI updates go back through `GLib.idle_add`
- Parsers are pure functions, kept testable without a GTK stack

## Project Structure

```
platforms/
├── macos/
│   ├── Sources/
│   │   ├── PortKillerApp.swift    # Entry point
│   │   ├── Managers/              # State & scanning
│   │   ├── Models/                # Data models
│   │   └── Views/                 # SwiftUI views
│   ├── Resources/                 # Assets, Info.plist
│   └── scripts/                   # Build scripts
├── windows/
│   └── PortKiller/                # .NET WPF project
└── linux/
    ├── port-killer.py             # Entry point
    ├── install.sh                 # Launcher + autostart installer
    ├── src/
    │   ├── scanner.py             # ss/lsof parsing, process killing
    │   ├── config.py              # Persisted preferences
    │   ├── services/              # Clipboard, Cloudflare, k8s
    │   └── ui/                    # Tray, window, dialogs
    └── tests/                     # Parser tests

portkiller-core/                   # Rust core (Linux only)
├── src/scanner/                   # Port scanning
└── src/process/                   # Process termination
```
