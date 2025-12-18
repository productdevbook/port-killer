# PortKiller Style Guide

This document defines the coding standards and conventions for the PortKiller project.

## Table of Contents

- [Swift Language](#swift-language)
- [Naming Conventions](#naming-conventions)
- [SwiftUI Patterns](#swiftui-patterns)
- [Concurrency](#concurrency)
- [File Organization](#file-organization)
- [Documentation](#documentation)
- [Code Quality](#code-quality)

## Swift Language

### Version and Features

- **Swift 6.0** is required
- Use modern Swift features (async/await, actors, structured concurrency)
- Enable **strict concurrency checking**
- Avoid legacy Objective-C patterns unless interfacing with system APIs

### Type Inference

Use type inference where it improves readability:

```swift
// Good - type is clear from context
let ports = scanner.scanPorts()
let count = ports.count

// Avoid - unnecessary explicit type
let ports: [PortInfo] = scanner.scanPorts()

// Good - explicit type adds clarity
let timeout: TimeInterval = 5.0
```

### Optionals

Prefer optional chaining and nil coalescing:

```swift
// Good
let name = port.processName ?? "Unknown"
window?.makeKeyAndOrderFront(nil)

// Avoid
if let processName = port.processName {
    name = processName
} else {
    name = "Unknown"
}
```

Use `guard` for early returns:

```swift
// Good
guard let port = selectedPort else { return }
// Use port here...

// Avoid
if selectedPort != nil {
    let port = selectedPort!
    // Use port here...
}
```

### Error Handling

Use `try?` for non-critical operations:

```swift
// Good - we don't care if this fails
try? await Task.sleep(for: .milliseconds(500))

// Good - critical operation, handle errors
do {
    try process.run()
    process.waitUntilExit()
} catch {
    print("Failed to run process: \(error)")
    return false
}
```

## Naming Conventions

Follow [Apple's Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).

### Types

- Use `PascalCase` for types and protocols
- Use descriptive, self-documenting names
- Avoid abbreviations unless widely understood

```swift
// Good
struct PortInfo { }
class AppState { }
enum ProcessType { }
protocol PortScanning { }

// Avoid
struct PI { }
class AS { }
enum PT { }
```

### Variables and Functions

- Use `camelCase` for variables, functions, and parameters
- Boolean variables should read as assertions

```swift
// Good
var isScanning = false
var canCheckForUpdates = true
func killProcess(pid: Int) { }

// Avoid
var scanning = false  // Unclear type
var able_to_check = true  // Wrong case
func kill(p: Int) { }  // Unclear parameter
```

### Constants

- Use static properties in enums for constants
- Group related constants together

```swift
// Good
enum UIConstants {
    static let width: CGFloat = 340
    static let maxHeight: CGFloat = 400
}

// Avoid
let MENU_BAR_WIDTH = 340  // Wrong case
let menuBarWidth = 340  // Should be grouped with related constants
```

### Enums

- Use lowercase for enum cases
- Omit prefixes when context is clear

```swift
// Good
enum ProcessType {
    case webServer
    case database
    case development
}

let type: ProcessType = .webServer  // Context clear

// Avoid
enum ProcessType {
    case ProcessTypeWebServer  // Redundant prefix
    case process_type_database  // Wrong case
}
```

## SwiftUI Patterns

### State Management

Use `@Observable` macro for state objects (not `ObservableObject`):

```swift
// Good - Modern @Observable
@Observable
@MainActor
final class AppState {
    var ports: [PortInfo] = []
    var isScanning = false
}

// Avoid - Legacy ObservableObject
@MainActor
final class AppState: ObservableObject {
    @Published var ports: [PortInfo] = []
    @Published var isScanning = false
}
```

### View Structure

Keep views focused and under 200 lines:

```swift
// Good - Single responsibility
struct PortListView: View {
    let ports: [PortInfo]

    var body: some View {
        List(ports) { port in
            PortRowView(port: port)
        }
    }
}

// Avoid - Too many responsibilities
struct MainView: View {
    var body: some View {
        // 500 lines of nested views...
    }
}
```

Extract complex views into separate components:

```swift
// Good
struct PortDetailView: View {
    let port: PortInfo

    var body: some View {
        VStack {
            PortHeader(port: port)
            PortInfo(port: port)
            PortActions(port: port)
        }
    }
}

// Each component is focused and reusable
```

### View Modifiers

Use custom view modifiers for repeated styling:

```swift
// Good
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color.white)
            .cornerRadius(8)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// Usage
Text("Hello").cardStyle()
```

## Concurrency

### MainActor Isolation

Mark UI-related types with `@MainActor`:

```swift
// Good
@Observable
@MainActor
final class AppState {
    var ports: [PortInfo] = []

    func refresh() async {
        // Runs on main thread automatically
        ports = await scanner.scanPorts()
    }
}

// Avoid
@Observable
final class AppState {
    var ports: [PortInfo] = []

    func refresh() async {
        // May run on background thread - UI updates will crash
        ports = await scanner.scanPorts()
    }
}
```

### Actors

Use actors for thread-safe state:

```swift
// Good
actor PortScanner {
    func scanPorts() async -> [PortInfo] {
        // Thread-safe by default
    }

    func killProcess(pid: Int) async -> Bool {
        // Thread-safe by default
    }
}
```

### Sendable

Mark types as `Sendable` when they cross concurrency boundaries:

```swift
// Good
struct PortInfo: Sendable {
    let port: Int
    let pid: Int
    let processName: String
}

// Model can be safely passed between actors
```

### Task Management

Store tasks that need cancellation:

```swift
// Good
@ObservationIgnored
private nonisolated(unsafe) var refreshTask: Task<Void, Never>?

func startAutoRefresh() {
    refreshTask = Task {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

deinit {
    refreshTask?.cancel()
}
```

## File Organization

### File Structure

Organize files by feature/responsibility:

```
Sources/
├── PortKillerApp.swift       # App entry point
├── AppState.swift             # Main app state
├── Constants.swift            # App constants
├── Models/                    # Data models
│   ├── Models.swift
│   └── PortFilter.swift
├── Managers/                  # Business logic
│   ├── UpdateManager.swift
│   └── SponsorManager.swift
├── Services/                  # External services
│   └── SponsorsService.swift
├── Views/                     # UI components
│   ├── MainWindowView.swift
│   ├── SettingsView.swift
│   └── Components/
│       ├── PortTableView.swift
│       └── AddPortPopover.swift
└── PortScanner.swift          # Port scanning logic
```

### File Header

Each file should start with imports, then content:

```swift
import Foundation
import SwiftUI
import Defaults

// MARK: - Model Definition

/**
 * PortInfo represents a process listening on a network port.
 */
struct PortInfo: Identifiable, Sendable {
    // ...
}
```

### MARK Comments

Use `// MARK:` to organize code within files:

```swift
class AppState {
    // MARK: - Properties
    var ports: [PortInfo] = []

    // MARK: - Initialization
    init() { }

    // MARK: - Port Operations
    func refresh() async { }
    func killPort(_ port: PortInfo) async { }

    // MARK: - Favorites
    func toggleFavorite(_ port: Int) { }

    // MARK: - Private Methods
    private func updatePorts(_ newPorts: [PortInfo]) { }
}
```

Standard sections (in order):
1. Properties
2. Initialization
3. Public Methods (grouped by feature)
4. Private Methods

## Documentation

### JSDoc-Style Comments

Document all public APIs with JSDoc-style comments:

```swift
/**
 * Scans all listening TCP ports using lsof.
 *
 * Executes: `lsof -iTCP -sTCP:LISTEN -P -n +c 0`
 *
 * @returns Array of PortInfo objects representing all listening ports
 */
func scanPorts() async -> [PortInfo] {
    // Implementation
}

/**
 * Kills a process by sending a termination signal.
 *
 * @param pid - The process ID to kill
 * @param force - If true, sends SIGKILL (-9) instead of SIGTERM (-15)
 * @returns True if the kill command executed successfully
 */
func killProcess(pid: Int, force: Bool = false) async -> Bool {
    // Implementation
}
```

### Inline Comments

Use inline comments for complex logic:

```swift
// CRITICAL: Read data BEFORE waitUntilExit to avoid deadlock
// If pipe buffer fills up, ps will block waiting to write more data.
let data = pipe.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()
```

### Property Documentation

Document non-obvious properties:

```swift
/// Cached favorites set, synced with UserDefaults
private var _favorites: Set<Int> = Defaults[.favorites] {
    didSet { Defaults[.favorites] = _favorites }
}

/// Whether a port scan is currently in progress
var isScanning = false
```

## Code Quality

### Line Length

- Keep lines under 120 characters when possible
- Break long function calls into multiple lines

```swift
// Good
let controller = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)

// Avoid - too long
let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
```

### Function Length

- Keep functions under 50 lines
- Extract complex logic into helper functions

```swift
// Good
func parseLsofOutput(_ output: String) -> [PortInfo] {
    let lines = output.components(separatedBy: .newlines)
    var ports: [PortInfo] = []

    for line in lines.dropFirst() {
        guard let port = parseLineToPort(line) else { continue }
        ports.append(port)
    }

    return ports
}

private func parseLineToPort(_ line: String) -> PortInfo? {
    // Focused parsing logic
}
```

### Complexity

Avoid deeply nested code:

```swift
// Good - Early returns
guard !line.isEmpty else { continue }
guard components.count >= 9 else { continue }
guard let pid = Int(components[1]) else { continue }

// Avoid - Nested ifs
if !line.isEmpty {
    if components.count >= 9 {
        if let pid = Int(components[1]) {
            // Deep nesting...
        }
    }
}
```

### Magic Numbers

Define constants instead of magic numbers:

```swift
// Good
enum AppConstants {
    static let defaultRefreshInterval: Int = 5
    static let maxCommandLength: Int = 200
}

let interval = AppConstants.defaultRefreshInterval

// Avoid
try? await Task.sleep(for: .seconds(5))  // Why 5?
let trimmed = command.prefix(200)  // Why 200?
```

### DRY (Don't Repeat Yourself)

Extract repeated code into functions:

```swift
// Good
func createPort(port: Int, processName: String) -> PortInfo {
    PortInfo.active(
        port: port,
        pid: 0,
        processName: processName,
        address: "127.0.0.1",
        user: "user",
        command: processName,
        fd: "19u"
    )
}

let nodePort = createPort(port: 3000, processName: "node")
let nginxPort = createPort(port: 8080, processName: "nginx")
```

## Testing

### Test Organization

Use descriptive test names:

```swift
@Test("Detects nginx as web server")
func detectNginx() {
    #expect(ProcessType.detect(from: "nginx") == .webServer)
}

@Test("Search matches process name case insensitively")
func searchMatchesProcessNameCaseInsensitive() {
    let filter = PortFilter(searchText: "NODE")
    let port = createPort(processName: "node")
    #expect(filter.matches(port, favorites: [], watched: []))
}
```

### Test Structure

Follow Arrange-Act-Assert pattern:

```swift
@Test("Port range filter excludes ports outside range")
func portRangeFilter() {
    // Arrange
    var filter = PortFilter()
    filter.minPort = 3000
    filter.maxPort = 5000

    // Act
    let portInRange = createPort(port: 4000)
    let portOutOfRange = createPort(port: 6000)

    // Assert
    #expect(filter.matches(portInRange, favorites: [], watched: []))
    #expect(!filter.matches(portOutOfRange, favorites: [], watched: []))
}
```

## Common Patterns

### Singleton-like Managers

For app-wide managers:

```swift
@Observable
@MainActor
final class AppState {
    // Shared state accessible throughout the app
}

// Usage in SwiftUI
@Environment(AppState.self) private var appState
```

### Defaults Integration

Use cached properties for UserDefaults:

```swift
// In Defaults.Keys extension
static let favorites = Key<Set<Int>>("favorites", default: [])

// In AppState
private var _favorites: Set<Int> = Defaults[.favorites] {
    didSet { Defaults[.favorites] = _favorites }
}

var favorites: Set<Int> {
    get { _favorites }
    set { _favorites = newValue }
}
```

### Command Execution

Pattern for running system commands:

```swift
func runCommand(path: String, args: [String]) async -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}
```

## Additional Resources

- [Swift.org - API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [Apple - The Swift Programming Language](https://docs.swift.org/swift-book/)
- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [SwiftUI Best Practices](https://developer.apple.com/documentation/swiftui)

---

**Remember:** These are guidelines, not absolute rules. Use your best judgment and prioritize code clarity and maintainability.
