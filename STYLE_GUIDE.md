# PortKiller Style Guide (macOS)

PortKiller for macOS targets macOS 27 on Apple silicon and Swift 6.4. There is no compatibility code for older systems.

## Package

- `platforms/macos` is a Swift package. Swift tools 6.4, `platforms: [.macOS(.v27)]`.
- Every target enables `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `ExistentialAny`, `MemberImportVisibility`, `InternalImportsByDefault`, `ImmutableWeakCaptures` and `strictMemorySafety()`.
- `PortKillerKit` holds everything that doesn't need AppKit or SwiftUI: port scanning, process control, kubectl and cloudflared, rules, persistence formats. Its types are `Sendable` and nonisolated, and it's what the tests cover.
- `PortKiller` is the app. It builds with `defaultIsolation(MainActor.self)`.
- Dependencies stay small and first-party where possible: swift-subprocess, swift-collections, swift-async-algorithms, and Sparkle for updates.

## Concurrency

- Code runs on the caller's actor by default. Mark work that must leave the main actor `@concurrent` (scanning, probing, signalling processes, running commands).
- Name long-lived tasks: `Task(name: "Port scan loop") { ... }`.
- Tasks own external processes. Starting a port forward or tunnel starts a task that runs the process through `CommandRunner.stream`; stopping cancels the task and Subprocess tears the process down.
- Use `Mutex` for shared mutable state in the Kit; don't add actors for bookkeeping that a lock covers.
- Use `AsyncTimerSequence` for fixed intervals, `Task.sleep` only for one-off delays and backoff.
- Use typed throws where callers handle specific failures (`KubectlError`, `TerminationError`).

## State

- One `@Observable` store per concern (`PortStore`, `PortForwardStore`, `TunnelStore`, `SponsorStore`), created by `AppModel` and injected with `.environment(model)`.
- `Preferences` owns everything persisted. Properties write to `UserDefaults` in `didSet`, using the same keys and value formats as PortKiller 3 so existing settings carry over.
- Mark state that views don't read `@ObservationIgnored`.
- Values that cross actors are structs from the Kit; reference types stay on the main actor.

## Views

- The window follows Liman: a searchable sidebar with Overview and one row per process, port forward, tunnel and plugin item; a node graph in the middle; and an inspector whose tabs are toolbar toggles.
- The graph is built by `PortGraph` in the Kit: providers (processes, port forwards, plugin items) show their ports as pins, and ports connect to consumers (Favorites, Watch, Quick Tunnel, tunnels, auto-kill rules, plugin actions). Wires take the color of the consumer they lead to. Overview shows everything; selecting an item shows `PortGraph.focused(on:)`. Dragging from a port onto a consumer goes through `PortGraph.change(linking:to:)` and `AppModel.apply(_:)`, so new node kinds are added in the Kit first.
- Keep the toolbar the same for every selection and disable what doesn't apply, so switching items doesn't move controls.
- Sidebar rows use `ItemRow` and `ItemIcon`. Inspector tabs are grouped `Form`s; use `InfoRow` for read-only values and `Label` with an SF Symbol for controls. A tab that doesn't apply shows `ContentUnavailableView` with the tab's symbol.
- Use Liquid Glass only for controls that float over content, such as the menu bar footer. Don't draw custom materials or shadows.
- Use `ContentUnavailableView` for empty, missing and error states.
- Keep view structs small and put actions in the stores. Views don't run processes or call the scanner; persisted settings go through `Preferences`, and `@AppStorage` is only for view state such as the selected settings tab.
- Use `.safeAreaBar` for status and action bars, `.alert(error:)` and `.confirmationDialog` for errors and destructive actions.

## Plugins

- Plugins are executables that exchange JSON with PortKiller; [PLUGINS.md](platforms/macos/PLUGINS.md) is the contract. Change it together with `PluginManifest` and `PluginProtocol`, and keep `apiVersion` compatible.
- Plugins only provide data. PortKiller draws their sections, forms, results and actions with the same native views as everything else.
- Never run a plugin that isn't turned on in Settings, or one whose required settings are empty.
- Run plugin actions through `PluginStore.run`, so confirmations, inputs, history and results behave the same from every menu, the inspector and the graph.
- Example plugins in `platforms/macos/Plugins` run on the `/bin/bash` that ships with macOS and are covered by `ExamplePluginTests`.

## System APIs

- Read ports and processes with `libproc` and `sysctl` in `PortScanner`; don't parse `lsof` or `ps`.
- Mark every unsafe operation with `unsafe`. Keep it in the Kit, or behind a small `@safe` type in the app such as `HotKeyCenter` for Carbon hot keys.
- Run external tools with `CommandRunner` and find them with `CommandLineTool`, which also knows Homebrew, Rancher Desktop, OrbStack and Docker Desktop locations.
- Use `SMAppService` for login items, `UNUserNotificationCenter` for notifications, typed `NotificationCenter` messages for AppKit events, and Foundation Models for on-device explanations.

## Code

- Don't write comments. Add one line only when the code can't say something: an outside tool's odd behaviour or a constraint that looks wrong without it.
- Name things for what they are in the domain: `ListeningPort`, `PortForwardSession`, `QuickTunnel`.
- Prefer `guard` and early returns, `if let x` shorthand, and `switch` expressions.
- No force unwraps outside tests.

## Tests

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`) and cover `PortKillerKit`.
- Use parameterized tests for tables of inputs.
- Test behaviour through public API; parsers take strings or `Data` so tests don't need real processes.

## Build

- `swift build` and `swift test` from `platforms/macos`.
- `Scripts/build-app.sh` builds the release app bundle in `build/PortKiller.app`: it compiles `AppIcon.icon` with `actool`, embeds Sparkle and signs ad hoc unless `SIGN_IDENTITY` is set.
