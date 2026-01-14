# Contributing

## Requirements

- **macOS 15.0+** / **Windows 10+**
- **Xcode 16+** with Swift 6.0 (for macOS)
- **.NET 9 SDK** (for Windows)

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
└── windows/
    └── PortKiller/                # .NET WPF project
```
