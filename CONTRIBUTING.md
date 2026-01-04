# Contributing

## Requirements

- **macOS 15.0+** - This is a macOS-only menu bar app
- **Xcode 16+** with Swift 6.0

## Setup

```bash
git clone https://github.com/productdevbook/port-killer.git
cd port-killer
```

## Running the App

```bash
# Option 1: Xcode (recommended)
open Package.swift
# Press ▶️ to run

# Option 2: Build script
./scripts/build-app.sh && open .build/release/PortKiller.app
```

> ⚠️ `swift run` doesn't work for menu bar apps - use Xcode or the build script.

## Building

```bash
swift build              # Debug
swift build -c release   # Release
./scripts/build-app.sh   # App bundle (release)
./scripts/build-debug.sh # App bundle (debug, for profiling)
```

## Profiling with Instruments

To profile the app with Instruments (memory, CPU, etc.):

```bash
# Build debug version with get-task-allow entitlement
./scripts/build-debug.sh
```

Then in Instruments:
1. Open **Instruments** (Xcode → Open Developer Tool → Instruments)
2. Select **Allocations** or **Leaks** template
3. **Target → Launch → Choose Target...**
4. Select: `.build/debug/PortKiller.app`
5. Click **Record**

> Note: Release builds cannot be profiled due to macOS security (SIP). Always use the debug build script for profiling.

## Pull Requests

1. Fork the repo
2. Create a branch (`git checkout -b feature/my-feature`)
3. Make changes and test locally
4. Commit (`git commit -m "feat: add feature"`)
5. Push and create PR

## Code Style

- Swift 6.0 with strict concurrency
- SwiftUI for UI
- `@Observable` for state management
- Keep files under 300 lines

## Project Structure

```
Sources/
├── PortKillerApp.swift    # Entry point
├── Managers/              # State & scanning
├── Models/                # Data models
└── Views/                 # SwiftUI views
```
