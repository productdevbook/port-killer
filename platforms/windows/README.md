# PortKiller for Windows

A native Windows app for finding and killing processes on open ports. Perfect for developers who need to quickly free up ports like 3000, 8080, 5173, etc.

## Features

- 🔍 Auto-discovers listening TCP ports
- ⚡ One-click process termination
- 🔄 Auto-refresh every 5 seconds
- 🔎 Search by port or process name
- ⭐ Favorite ports for quick access
- 👁️ Watch ports and get notifications
- 🎨 Modern Windows 11 design with WinUI 3
- 🔔 System tray integration

## Requirements

- Windows 10 version 1809 (build 17763) or later
- Windows 11 (recommended)
- .NET 9.0 Runtime
- Administrator privileges (required to kill processes)

## Installation

### Option 1: Download from GitHub Releases (Recommended)

1. Go to [GitHub Releases](https://github.com/productdevbook/port-killer/releases)
2. Download the latest `PortKiller-vX.X.X-windows-x64.zip` (or `arm64` for ARM devices)
3. Extract the ZIP to a folder of your choice
4. Run `PortKiller.exe`

> **Note:** Requires [.NET 9 Runtime](https://dotnet.microsoft.com/download/dotnet/9.0) to be installed.

### Option 2: Build from Source

1. Clone the repository:
```bash
git clone https://github.com/productdevbook/port-killer.git
cd port-killer/platforms/windows
```

2. Open in Visual Studio 2022 or later:
```bash
cd PortKiller
dotnet restore
dotnet build
```

3. Run the application:
```bash
dotnet run
```

### Option 3: Visual Studio

1. Open `PortKiller.csproj` in Visual Studio 2022
2. Build the solution (Ctrl+Shift+B)
3. Run (F5) or Debug

### Option 4: Package for Distribution

```bash
dotnet publish -c Release -r win-x64 --self-contained
```

## Usage

### Basic Operations

1. **View All Ports**: The app automatically scans and displays all listening TCP ports
2. **Kill a Process**: Click the kill button next to any port
3. **Search**: Use the search box to filter by port number or process name
4. **Refresh**: Click the refresh button or wait for auto-refresh

### Favorites

- Click on a port to view details
- Click "Add to Favorites" to mark important ports
- Access favorites from the sidebar

### Watched Ports

- Click on a port and select "Watch Port"
- Get notifications when the port starts or stops
- Manage watched ports from the sidebar

### Sidebar Navigation

- **All Ports**: View all listening ports
- **Favorites**: Quick access to favorite ports
- **Watched**: Monitored ports with notifications
- **Process Types**: Filter by Web Server, Database, Development, System, Other
- **Settings**: Configure refresh interval and notifications

### System Tray

- The app runs in the system tray
- Left-click the tray icon to show/hide the window
- Right-click for context menu

## Architecture

### Technology Stack

- **Language**: C# 12 with .NET 8
- **UI Framework**: WinUI 3 (Windows App SDK)
- **Architecture**: MVVM with CommunityToolkit.Mvvm
- **DI Container**: Microsoft.Extensions.DependencyInjection

### Project Structure

```
PortKiller/
├── Models/              # Data models (PortInfo, ProcessType, etc.)
├── Services/            # Business logic services
│   ├── PortScannerService.cs       # Scans ports using Win32 API
│   ├── ProcessKillerService.cs     # Terminates processes
│   ├── SettingsService.cs          # Persistent settings
│   └── NotificationService.cs      # Windows notifications
├── ViewModels/          # MVVM ViewModels
│   └── MainViewModel.cs
├── App.xaml             # Application entry point
└── MainWindow.xaml      # Main UI
```

### How It Works

#### Port Scanning

The app uses the Windows `GetExtendedTcpTable` API to get all TCP connections:

```csharp
// Get all listening TCP connections with process IDs
GetExtendedTcpTable(IntPtr, ref int, bool, AF_INET, TCP_TABLE_OWNER_PID_LISTENER, 0);
```

This is equivalent to macOS `lsof -iTCP -sTCP:LISTEN` but more efficient.

#### Process Information

Uses WMI (Windows Management Instrumentation) to get detailed process info:

```csharp
// Get command line
ManagementObjectSearcher("SELECT CommandLine FROM Win32_Process WHERE ProcessId = {pid}")

// Get process owner
OpenProcessToken() + WindowsIdentity
```

#### Process Termination

Two-stage approach:
1. Try graceful shutdown with `CloseMainWindow()`
2. Force kill with `Process.Kill(entireProcessTree: true)`

## Development

### Prerequisites

- Visual Studio 2022 17.8 or later
- Windows App SDK 1.5 or later
- .NET 8 SDK

### Build

```bash
dotnet build -c Debug
```

### Test

```bash
dotnet test
```

### Package for Distribution

```bash
dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true
```

## Known Limitations

- Requires administrator privileges to kill processes
- Cannot kill system processes (by design)
- IPv6 support is limited (IPv4 only currently)
- Some processes may require force kill

## Troubleshooting

### "Access Denied" when killing process

Run the app as Administrator. Right-click and select "Run as administrator".

### Port scan not showing all ports

Make sure you're running as Administrator. Some ports require elevated privileges to view.

### App doesn't start

1. Check Windows version (Windows 10 1809+ or Windows 11)
2. Install .NET 8 Runtime
3. Install Windows App SDK Runtime

## Comparison with macOS Version

| Feature | macOS | Windows |
|---------|-------|---------|
| Port Scanning | `lsof` | Win32 API |
| Process Killing | `kill -15/-9` | `Process.Kill()` |
| UI Framework | SwiftUI | WinUI 3 |
| System Tray | MenuBarExtra | TaskbarIcon |
| Notifications | UNNotification | AppNotification |
| Settings Storage | UserDefaults | ApplicationData |

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for development guidelines.

## License

MIT License - see [LICENSE](../../LICENSE).

## Credits

Windows port by the PortKiller team. Original macOS version available at [github.com/productdevbook/port-killer](https://github.com/productdevbook/port-killer).
