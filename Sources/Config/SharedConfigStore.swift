import Foundation

/// Shared configuration between CLI and macOS app
/// Stored at ~/.portkiller/config.json
@MainActor
final class SharedConfigStore {
    static let shared = SharedConfigStore()

    private let configPath: URL
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    /// Callback when config changes externally
    var onConfigChanged: (() -> Void)?

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".portkiller")
        self.configPath = configDir.appendingPathComponent("config.json")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        startWatching()
    }

    deinit {
        fileMonitor?.cancel()
    }

    // MARK: - File Watching

    private func startWatching() {
        // Ensure file exists
        if !FileManager.default.fileExists(atPath: configPath.path) {
            try? "{}".write(to: configPath, atomically: true, encoding: .utf8)
        }

        fileDescriptor = open(configPath.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )

        fileMonitor?.setEventHandler { [weak self] in
            self?.onConfigChanged?()
        }

        fileMonitor?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        fileMonitor?.resume()
    }

    // MARK: - Load/Save

    func load() -> SharedConfig {
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(SharedConfig.self, from: data) else {
            return SharedConfig(favorites: [], watchedPorts: [])
        }
        return config
    }

    func save(_ config: SharedConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }

        // Pretty print
        if let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? prettyData.write(to: configPath)
        } else {
            try? data.write(to: configPath)
        }
    }

    // MARK: - Convenience

    var favorites: Set<Int> {
        get { Set(load().favorites) }
        set {
            var config = load()
            config.favorites = Array(newValue)
            save(config)
        }
    }

    var watchedPorts: [WatchedPort] {
        get { load().watchedPorts.map { $0.toWatchedPort() } }
        set {
            var config = load()
            config.watchedPorts = newValue.map { SharedWatchedPort(from: $0) }
            save(config)
        }
    }
}

// MARK: - Shared Config Types (JSON compatible with CLI)

struct SharedConfig: Codable {
    var favorites: [Int]
    var watchedPorts: [SharedWatchedPort]
}

struct SharedWatchedPort: Codable {
    let id: String
    let port: Int
    var notifyOnStart: Bool
    var notifyOnStop: Bool

    init(from watchedPort: WatchedPort) {
        self.id = watchedPort.id.uuidString
        self.port = watchedPort.port
        self.notifyOnStart = watchedPort.notifyOnStart
        self.notifyOnStop = watchedPort.notifyOnStop
    }

    func toWatchedPort() -> WatchedPort {
        // Parse UUID from string, generate new one if invalid
        let uuid = UUID(uuidString: id) ?? UUID()
        return WatchedPort(id: uuid, port: port, notifyOnStart: notifyOnStart, notifyOnStop: notifyOnStop)
    }
}

// MARK: - WatchedPort Extension for init with id

extension WatchedPort {
    init(id: UUID, port: Int, notifyOnStart: Bool = true, notifyOnStop: Bool = true) {
        self.id = id
        self.port = port
        self.notifyOnStart = notifyOnStart
        self.notifyOnStop = notifyOnStop
    }
}
