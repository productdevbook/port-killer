# PortKiller Backend

Rust workspace containing the core library, CLI, and FFI bindings for Swift integration.

## Structure

```
backend/
├── Cargo.toml      # Workspace root
├── core/           # portkiller-core library
│   └── src/
│       ├── lib.rs
│       ├── config.rs
│       ├── killer.rs
│       ├── error.rs
│       ├── models/
│       └── scanner/
├── cli/            # portkiller CLI binary
│   └── src/
│       ├── main.rs
│       ├── commands/
│       └── tui/
└── ffi/            # UniFFI bindings for Swift
    └── src/
        ├── lib.rs
        └── lib.udl
```

## Quick Start

```bash
# Build everything
cargo build --release

# Run CLI
cargo run --bin portkiller

# Install globally
cargo install --path cli
```

---

## CLI Usage

### Basic Commands

```bash
# List all listening ports
portkiller list
portkiller ls                    # alias

# Filter by port or name
portkiller list --port 3000
portkiller list --name node

# Kill process on a port
portkiller kill 3000
portkiller kill 3000 --force     # SIGKILL immediately

# Manage favorites
portkiller fav add 3000
portkiller fav rm 3000
portkiller fav list

# Manage watched ports
portkiller watch add 5432
portkiller watch rm 5432
portkiller watch list

# Show configuration
portkiller config

# JSON output
portkiller list --json
portkiller config --json

# Disable TUI (list mode)
portkiller --no-tui
```

### TUI Mode

Run `portkiller` without arguments to launch interactive TUI.

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `g` | Go to first |
| `G` | Go to last |
| `x` / `Del` | Kill selected process |
| `f` | Toggle favorite |
| `w` | Toggle watch |
| `/` | Start search |
| `Enter` | End search |
| `r` | Refresh |
| `q` / `Esc` | Quit |

---

## Library Usage (portkiller-core)

### Installation

```toml
[dependencies]
portkiller-core = { path = "backend/core" }
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
```

### Scan Ports

```rust
use portkiller_core::PortScanner;

#[tokio::main]
async fn main() {
    let scanner = PortScanner::new();
    let ports = scanner.scan().await.unwrap();

    for port in &ports {
        println!("{}: {} (PID: {})", port.port, port.process_name, port.pid);
    }
}
```

### Kill a Process

```rust
use portkiller_core::ProcessKiller;

#[tokio::main]
async fn main() {
    let killer = ProcessKiller::new();

    // Graceful kill (SIGTERM → wait 500ms → SIGKILL)
    killer.kill_gracefully(1234).await.unwrap();

    // Force kill (SIGKILL immediately)
    killer.kill(1234, true).await.unwrap();
}
```

### Manage Configuration

```rust
use portkiller_core::ConfigStore;

#[tokio::main]
async fn main() {
    let store = ConfigStore::new().unwrap();

    // Favorites
    store.add_favorite(3000).await.unwrap();
    let favorites = store.get_favorites().await.unwrap();

    // Watched ports
    store.add_watched_port(5432).await.unwrap();
    let watched = store.get_watched_ports().await.unwrap();
}
```

### Filter Ports

```rust
use portkiller_core::{PortFilter, ProcessType, filter_ports};

let filter = PortFilter::new()
    .with_search("node")
    .with_port_range(Some(3000), Some(9000))
    .with_process_types([ProcessType::Development]);

let filtered = filter_ports(&ports, &filter, &favorites, &watched);
```

---

## Configuration

Location: `~/.portkiller/config.json`

```json
{
  "favorites": [3000, 8080],
  "watchedPorts": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "port": 5432,
      "notifyOnStart": true,
      "notifyOnStop": true
    }
  ]
}
```

This format is compatible with the Swift macOS app for seamless sync.

---

## Swift Integration (FFI)

The `ffi` crate provides UniFFI bindings for the Swift macOS app.

### Build XCFramework

```bash
# From project root
./scripts/build-rust-xcframework.sh
```

This creates:
- `Frameworks/PortKillerCore.xcframework` - Universal static library
- `Sources/RustBridge/portkiller_ffi.swift` - Generated Swift bindings

### Architecture

```
Swift App (PortKiller.app)
    │
    ▼
RustPortScanner.swift (wrapper)
    │
    ▼
portkiller_ffi.swift (UniFFI generated)
    │
    ▼
PortKillerCore.xcframework (static library)
    │
    ▼
portkiller-core (Rust library)
```

### Exposed API

```swift
// Create scanner
let scanner = RustScanner()

// Scan ports
let ports: [RustPortInfo] = try scanner.scanPorts()

// Kill process (graceful: SIGTERM → 500ms → SIGKILL)
let success: Bool = try scanner.killProcess(pid: 1234)

// Force kill (SIGKILL immediately)
let success: Bool = try scanner.forceKillProcess(pid: 1234)

// Check if process is running
let running: Bool = scanner.isProcessRunning(pid: 1234)
```

---

## Platform Support

| Platform | Core | CLI | Swift FFI |
|----------|------|-----|-----------|
| macOS | ✅ Full (lsof) | ✅ | ✅ |
| Linux | 🚧 Planned | ✅ | ❌ |
| Windows | 🚧 Planned | ✅ | ❌ |

---

## Development

```bash
# Run all tests
cargo test

# Run core tests only
cargo test -p portkiller-core

# Check formatting
cargo fmt --check

# Lint
cargo clippy

# Build release
cargo build --release
```

## License

MIT
