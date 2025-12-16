import Foundation

// MARK: - File Watching

protocol FileWatcherDelegate: AnyObject {
    func fileDidChange(at path: String)
}

class FileWatcher {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let path: String
    private weak var delegate: FileWatcherDelegate?
    
    init(path: String, delegate: FileWatcherDelegate) {
        self.path = path
        self.delegate = delegate
    }
    
    func startWatching() {
        guard FileManager.default.fileExists(atPath: path) else {
            print("FileWatcher: File does not exist at path: \(path)")
            return
        }
        
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("FileWatcher: Failed to open file at path: \(path)")
            return
        }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .background)
        )
        
        source?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.delegate?.fileDidChange(at: self.path)
        }
        
        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        
        source?.resume()
        print("FileWatcher: Started watching file at path: \(path)")
    }
    
    func stopWatching() {
        source?.cancel()
        source = nil
        print("FileWatcher: Stopped watching file at path: \(path)")
    }
    
    deinit {
        stopWatching()
    }
}

// MARK: - Configuration Errors

enum ConfigurationError: Error, LocalizedError {
    case invalidFormat(String)
    case validationFailed(String)
    case fileNotFound(String)
    case permissionDenied(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid configuration format: \(message)"
        case .validationFailed(let message):
            return "Configuration validation failed: \(message)"
        case .fileNotFound(let message):
            return "Configuration file not found: \(message)"
        case .permissionDenied(let message):
            return "Permission denied accessing configuration: \(message)"
        }
    }
}

// MARK: - String Extensions

extension String {
    func matches(regex pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(location: 0, length: self.count)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
}

// MARK: - Configuration Status

struct ConfigurationStatus {
    let isLoaded: Bool
    let isUsingCustomConfiguration: Bool
    let exactMatchCount: Int
    let patternMatchCount: Int
    let technologyKeywordCount: Int
    let actionKeywordCount: Int
    let namingConventionCount: Int
    let fallbackDescriptionCount: Int
    
    var totalEntries: Int {
        exactMatchCount + patternMatchCount + technologyKeywordCount + actionKeywordCount + namingConventionCount
    }
}

// MARK: - Description Database Models

struct DescriptionDatabase: Codable {
    let exactMatches: [String: String]
    let patternMatches: [PatternMatch]
    let technologyKeywords: [String: String]
    let actionKeywords: [String: String]
    let namingConventions: [PatternMatch]
    let fallbackDescriptions: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case exactMatches = "exact_matches"
        case patternMatches = "pattern_matches"
        case technologyKeywords = "technology_keywords"
        case actionKeywords = "action_keywords"
        case namingConventions = "naming_conventions"
        case fallbackDescriptions = "fallback_descriptions"
    }
}

struct PatternMatch: Codable {
    let pattern: String
    let description: String
    let category: String
    
    var compiledRegex: NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}

// MARK: - Performance Monitoring

struct PerformanceMetrics {
    var lookupCount: Int = 0
    var cacheHits: Int = 0
    var cacheMisses: Int = 0
    var averageLookupTime: Double = 0.0
    var memoryUsageBytes: Int = 0
    var lastMemoryCheck: Date = Date()
    
    var cacheHitRate: Double {
        guard lookupCount > 0 else { return 0.0 }
        return Double(cacheHits) / Double(lookupCount)
    }
    
    var memoryUsageMB: Double {
        return Double(memoryUsageBytes) / (1024 * 1024)
    }
}

// MARK: - Caching

struct CachedDescription {
    let description: ProcessDescription
    let timestamp: Date
    let accessCount: Int
    
    init(description: ProcessDescription) {
        self.description = description
        self.timestamp = Date()
        self.accessCount = 1
    }
    
    private init(description: ProcessDescription, timestamp: Date, accessCount: Int) {
        self.description = description
        self.timestamp = timestamp
        self.accessCount = accessCount
    }
    
    func withIncrementedAccess() -> CachedDescription {
        return CachedDescription(
            description: self.description,
            timestamp: self.timestamp,
            accessCount: self.accessCount + 1
        )
    }
}

// MARK: - Optimized Pattern Matching

struct CompiledPatternMatch {
    let pattern: String
    let description: String
    let category: String
    let compiledRegex: NSRegularExpression
    
    init?(from patternMatch: PatternMatch) {
        guard let regex = patternMatch.compiledRegex else { return nil }
        self.pattern = patternMatch.pattern
        self.description = patternMatch.description
        self.category = patternMatch.category
        self.compiledRegex = regex
    }
}

// MARK: - Process Description Service

actor ProcessDescriptionService: FileWatcherDelegate {
    private var database: DescriptionDatabase?
    private var isLoaded = false
    private var fileWatchers: [FileWatcher] = []
    private var watchedPaths: Set<String> = []
    
    // Performance optimization: Caching
    private var descriptionCache: [String: CachedDescription] = [:]
    private let maxCacheSize = 1000
    private let cacheExpirationTime: TimeInterval = 300 // 5 minutes
    
    // Performance optimization: Pre-compiled patterns
    private var compiledPatternMatches: [CompiledPatternMatch] = []
    private var compiledNamingConventions: [CompiledPatternMatch] = []
    
    // Performance monitoring
    private var performanceMetrics = PerformanceMetrics()
    private let memoryCheckInterval: TimeInterval = 30 // Check memory every 30 seconds
    
    // Built-in descriptions as fallback
    nonisolated let builtInDatabase = DescriptionDatabase(
        exactMatches: [
            // Development tools
            "node": "Node.js JavaScript runtime",
            "webpack-dev-server": "Webpack development server with hot reloading",
            "nodemon": "Node.js development tool with automatic restart",
            "rails": "Ruby on Rails web application framework",
            "vite": "Vite build tool and development server",
            "parcel": "Parcel web application bundler",
            "rollup": "Rollup JavaScript module bundler",
            "gulp": "Gulp task runner",
            "grunt": "Grunt task runner",
            "yarn": "Yarn package manager",
            "npm": "Node Package Manager",
            "pnpm": "PNPM package manager",
            
            // Programming languages and runtimes
            "python": "Python interpreter",
            "python3": "Python 3 interpreter",
            "java": "Java Virtual Machine",
            "ruby": "Ruby interpreter",
            "php": "PHP interpreter",
            "go": "Go programming language runtime",
            "rust": "Rust programming language runtime",
            "dotnet": ".NET runtime",
            
            // Web servers
            "nginx": "High-performance web server and reverse proxy",
            "apache2": "Apache HTTP Server",
            "httpd": "Apache HTTP Server daemon",
            "lighttpd": "Lightweight HTTP server",
            "caddy": "Caddy web server with automatic HTTPS",
            
            // Database services
            "mysql": "MySQL database server",
            "mysqld": "MySQL database daemon",
            "postgres": "PostgreSQL database server",
            "postgresql": "PostgreSQL database server",
            "mongod": "MongoDB database daemon",
            "mongodb": "MongoDB database server",
            "redis-server": "Redis in-memory data structure store",
            "redis": "Redis in-memory data structure store",
            "memcached": "Memcached distributed memory caching system",
            "elasticsearch": "Elasticsearch search and analytics engine",
            "kibana": "Kibana data visualization dashboard",
            
            // macOS system processes
            "launchd": "macOS system and service manager",
            "kernel_task": "macOS kernel task",
            "WindowServer": "macOS window management system",
            "Finder": "macOS file manager",
            "Dock": "macOS application dock",
            "SystemUIServer": "macOS system UI server",
            "loginwindow": "macOS login window process",
            "cfprefsd": "macOS Core Foundation preferences daemon",
            "mds": "macOS metadata server (Spotlight)",
            "mdworker": "macOS metadata worker process",
            "coreaudiod": "macOS Core Audio daemon",
            "bluetoothd": "macOS Bluetooth daemon",
            "wifid": "macOS Wi-Fi daemon",
            "networkd": "macOS network daemon",
            "syslogd": "macOS system logging daemon",
            
            // Development applications
            "code": "Visual Studio Code",
            "xcode": "Xcode IDE",
            "webstorm": "WebStorm IDE",
            "intellij": "IntelliJ IDEA",
            "eclipse": "Eclipse IDE",
            "atom": "Atom text editor",
            "sublime_text": "Sublime Text editor",
            
            // Browsers
            "chrome": "Google Chrome web browser",
            "firefox": "Mozilla Firefox web browser",
            "safari": "Safari web browser",
            "edge": "Microsoft Edge web browser",
            
            // Docker and containerization
            "docker": "Docker container runtime",
            "dockerd": "Docker daemon",
            "containerd": "Container runtime",
            "kubernetes": "Kubernetes container orchestration",
            "kubectl": "Kubernetes command-line tool",
            
            // Version control
            "git": "Git version control system",
            "svn": "Subversion version control",
            "hg": "Mercurial version control",
            
            // Application servers
            "tomcat": "Apache Tomcat server",
            "jetty": "Jetty web server",
            
            // Additional system processes
            "systemd": "System and service manager"
        ],
        patternMatches: [
            PatternMatch(pattern: ".*-dev-server$", description: "Development server with hot reloading", category: "development"),
            PatternMatch(pattern: ".*\\.dev$", description: "Development environment service", category: "development"),
            PatternMatch(pattern: ".*-server$", description: "Server application", category: "webServer"),
            PatternMatch(pattern: ".*-daemon$", description: "Background daemon service", category: "system"),
            PatternMatch(pattern: ".*-worker$", description: "Background worker process", category: "system"),
            PatternMatch(pattern: ".*-monitor$", description: "System monitoring service", category: "system"),
            PatternMatch(pattern: ".*-proxy$", description: "Proxy or gateway service", category: "webServer"),
            PatternMatch(pattern: ".*-api$", description: "API service or endpoint", category: "webServer"),
            PatternMatch(pattern: ".*sql.*", description: "Database service", category: "database"),
            PatternMatch(pattern: ".*db.*", description: "Database-related service", category: "database")
        ],
        technologyKeywords: [
            "python": "Python application or script",
            "java": "Java application or service",
            "node": "Node.js JavaScript application",
            "nodejs": "Node.js JavaScript application",
            "docker": "Docker container or service",
            "nginx": "Nginx web server",
            "apache": "Apache web server",
            "mysql": "MySQL database service",
            "postgres": "PostgreSQL database service",
            "postgresql": "PostgreSQL database service",
            "redis": "Redis in-memory data store",
            "mongo": "MongoDB database service",
            "mongodb": "MongoDB database service",
            "elasticsearch": "Elasticsearch search engine",
            "kibana": "Kibana analytics dashboard",
            "php": "PHP web application",
            "ruby": "Ruby application",
            "rails": "Ruby on Rails web application",
            "django": "Django Python web framework",
            "flask": "Flask Python web framework",
            "express": "Express.js web framework",
            "react": "React development server",
            "vue": "Vue.js development server",
            "angular": "Angular development server",
            "webpack": "Webpack build tool",
            "vite": "Vite build tool",
            "parcel": "Parcel bundler",
            "rollup": "Rollup bundler",
            "gulp": "Gulp task runner",
            "grunt": "Grunt task runner",
            "yarn": "Yarn package manager",
            "npm": "NPM package manager",
            "pnpm": "PNPM package manager",
            "go": "Go application",
            "rust": "Rust application",
            "dotnet": ".NET application",
            "spring": "Spring Framework application",
            "tomcat": "Apache Tomcat server",
            "jetty": "Jetty web server",
            "kubernetes": "Kubernetes service",
            "k8s": "Kubernetes service"
        ],
        actionKeywords: [
            "server": "Server application or service",
            "daemon": "Background system service",
            "worker": "Background worker process",
            "monitor": "System monitoring service",
            "proxy": "Proxy or gateway service",
            "api": "API service or endpoint",
            "web": "Web-related service",
            "db": "Database-related service",
            "cache": "Caching service",
            "queue": "Message queue service",
            "scheduler": "Task scheduling service",
            "logger": "Logging service",
            "auth": "Authentication service",
            "sync": "Synchronization service",
            "backup": "Backup service",
            "deploy": "Deployment service",
            "build": "Build service",
            "test": "Testing service",
            "dev": "Development service",
            "prod": "Production service",
            "staging": "Staging environment service"
        ],
        namingConventions: [
            PatternMatch(pattern: ".*d$", description: "System daemon or background service", category: "system"),
            PatternMatch(pattern: ".*ctl$", description: "Control or management utility", category: "system"),
            PatternMatch(pattern: ".*-server$", description: "Server application", category: "webServer"),
            PatternMatch(pattern: ".*-client$", description: "Client application", category: "other"),
            PatternMatch(pattern: ".*-service$", description: "Service application", category: "system"),
            PatternMatch(pattern: ".*-agent$", description: "Agent or monitoring service", category: "system"),
            PatternMatch(pattern: ".*-helper$", description: "Helper or utility process", category: "system"),
            PatternMatch(pattern: ".*-manager$", description: "Management service", category: "system"),
            PatternMatch(pattern: ".*-handler$", description: "Event or request handler", category: "system"),
            PatternMatch(pattern: ".*-processor$", description: "Data processing service", category: "system"),
            PatternMatch(pattern: ".*-gateway$", description: "Gateway or proxy service", category: "webServer"),
            PatternMatch(pattern: ".*-bridge$", description: "Bridge or integration service", category: "system"),
            PatternMatch(pattern: ".*-sync$", description: "Synchronization service", category: "system"),
            PatternMatch(pattern: ".*-watcher$", description: "File or system watcher", category: "system"),
            PatternMatch(pattern: ".*-scanner$", description: "Scanning or monitoring service", category: "system")
        ],
        fallbackDescriptions: [
            "development": "Development tool or server",
            "system": "System service or daemon",
            "database": "Database server",
            "webServer": "Web server or HTTP service",
            "other": "Application or service (exercise caution when terminating)"
        ]
    )
    
    init() {
        Task {
            await loadDescriptions()
        }
    }
    
    // MARK: - Public Interface
    
    func getDescription(for processName: String) async -> ProcessDescription {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Performance optimization: Check cache first
        if let cachedDescription = await getCachedDescription(for: processName) {
            await updatePerformanceMetrics(lookupTime: CFAbsoluteTimeGetCurrent() - startTime, cacheHit: true)
            return cachedDescription.description
        }
        
        if !isLoaded {
            await loadDescriptions()
        }
        
        let currentDatabase = database ?? builtInDatabase
        let lowercasedName = processName.lowercased()
        
        // 1. Try exact match first (highest priority)
        // Try both original case and lowercase for exact matches
        var exactDescription: String? = currentDatabase.exactMatches[lowercasedName]
        if exactDescription == nil {
            // Try original case for processes like "WindowServer", "Finder"
            exactDescription = currentDatabase.exactMatches[processName]
        }
        
        if let exactDescription = exactDescription {
            let category = inferCategory(from: processName, description: exactDescription)
            let description = ProcessDescription(
                text: exactDescription,
                category: category,
                confidence: .exact
            )
            await cacheDescription(for: processName, description: description)
            await updatePerformanceMetrics(lookupTime: CFAbsoluteTimeGetCurrent() - startTime, cacheHit: false)
            return description
        }
        
        // 2. Try pattern matches (second priority) - using pre-compiled patterns
        for compiledPattern in compiledPatternMatches {
            if compiledPattern.compiledRegex.firstMatch(in: lowercasedName, options: [], range: NSRange(location: 0, length: lowercasedName.count)) != nil {
                let category = ProcessCategory(rawValue: compiledPattern.category) ?? .other
                let description = ProcessDescription(
                    text: compiledPattern.description,
                    category: category,
                    confidence: .pattern
                )
                await cacheDescription(for: processName, description: description)
                await updatePerformanceMetrics(lookupTime: CFAbsoluteTimeGetCurrent() - startTime, cacheHit: false)
                return description
            }
        }
        
        // 3. Try technology keyword matching (third priority)
        for (keyword, descriptionText) in currentDatabase.technologyKeywords {
            if lowercasedName.contains(keyword.lowercased()) {
                let category = inferCategoryFromKeyword(keyword, type: .technology)
                let description = ProcessDescription(
                    text: descriptionText,
                    category: category,
                    confidence: .pattern
                )
                await cacheDescription(for: processName, description: description)
                await updatePerformanceMetrics(lookupTime: CFAbsoluteTimeGetCurrent() - startTime, cacheHit: false)
                return description
            }
        }
        
        // 4. Try action keyword matching (fourth priority)
        for (keyword, descriptionText) in currentDatabase.actionKeywords {
            if lowercasedName.contains(keyword.lowercased()) {
                let category = inferCategoryFromKeyword(keyword, type: .action)
                let description = ProcessDescription(
                    text: descriptionText,
                    category: category,
                    confidence: .pattern
                )
                await cacheDescription(for: processName, description: description)
                await updatePerformanceMetrics(lookupTime: CFAbsoluteTimeGetCurrent() - startTime, cacheHit: false)
                return description
            }
        }
        
        // 5. Try naming convention patterns (fifth priority) - using pre-compiled patterns
        for compiledConvention in compiledNamingConventions {
            if compiledConvention.compiledRegex.firstMatch(in: lowercasedName, options: [], range: NSRange(location: 0, length: lowercasedName.count)) != nil {
                let category = ProcessCategory(rawValue: compiledConvention.category) ?? .other
                let description = ProcessDescription(
                    text: compiledConvention.description,
                    category: category,
                    confidence: .pattern
                )
                await cacheDescription(for: processName, description: description)
                await updatePerformanceMetrics(lookupTime: CFAbsoluteTimeGetCurrent() - startTime, cacheHit: false)
                return description
            }
        }
        
        // 6. Intelligent fallback analysis (final fallback - ensures NO process is left without description)
        let (intelligentDescription, category) = generateIntelligentFallback(for: processName, database: currentDatabase)
        
        let description = ProcessDescription(
            text: intelligentDescription,
            category: category,
            confidence: .fallback
        )
        await cacheDescription(for: processName, description: description)
        await updatePerformanceMetrics(lookupTime: CFAbsoluteTimeGetCurrent() - startTime, cacheHit: false)
        return description
    }
    
    func loadDescriptions() async {
        // Performance optimization: Load in background to avoid blocking
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.performDatabaseLoad()
            }
        }
        
        // Performance optimization: Pre-compile regex patterns after loading
        await precompilePatterns()
        
        // Performance optimization: Initialize cache and memory monitoring
        await initializePerformanceMonitoring()
        
        // Set up file watching for dynamic reloading
        await setupFileWatching()
    }
    
    private func performDatabaseLoad() async {
        do {
            // Try to load from custom configuration first
            if let customDatabase = try await loadCustomDescriptions() {
                database = mergeDescriptions(builtin: builtInDatabase, custom: customDatabase)
                print("Successfully loaded and merged custom descriptions")
            } else {
                database = builtInDatabase
                print("No custom descriptions found, using built-in database")
            }
            isLoaded = true
        } catch let configError as ConfigurationError {
            // Handle configuration-specific errors with detailed logging
            database = builtInDatabase
            isLoaded = true
            print("Configuration Error: \(configError.localizedDescription)")
            print("Falling back to built-in descriptions to ensure service availability")
        } catch {
            // Handle any other unexpected errors
            database = builtInDatabase
            isLoaded = true
            print("Unexpected error loading custom descriptions: \(error.localizedDescription)")
            print("Falling back to built-in descriptions to ensure service availability")
        }
        
        // Validate that we have a working database
        if database == nil {
            print("Critical error: No database available, reinitializing with built-in database")
            database = builtInDatabase
        }
        
        // Log final database statistics
        if let db = database {
            print("Description database loaded successfully:")
            print("  - Exact matches: \(db.exactMatches.count)")
            print("  - Pattern matches: \(db.patternMatches.count)")
            print("  - Technology keywords: \(db.technologyKeywords.count)")
            print("  - Action keywords: \(db.actionKeywords.count)")
            print("  - Naming conventions: \(db.namingConventions.count)")
            print("  - Fallback descriptions: \(db.fallbackDescriptions.count)")
        }
    }
    
    func reloadDescriptions() async {
        print("Reloading description database...")
        let previousDatabase = database
        isLoaded = false
        
        // Performance optimization: Clear cache on reload
        await clearCache()
        
        await loadDescriptions()
        
        // Compare with previous database to detect changes
        if let prev = previousDatabase, let current = database {
            let prevCount = prev.exactMatches.count
            let currentCount = current.exactMatches.count
            
            if prevCount != currentCount {
                print("Database reload detected changes: \(prevCount) -> \(currentCount) exact matches")
            } else {
                print("Database reload completed, no changes in entry count")
            }
        }
        
        // Restart file watching after reload
        await setupFileWatching()
    }
    
    // MARK: - File Watching
    
    nonisolated func fileDidChange(at path: String) {
        print("FileWatcher: Detected change in description file: \(path)")
        Task {
            await self.reloadDescriptions()
        }
    }
    
    private func setupFileWatching() async {
        // Stop existing watchers
        await stopFileWatching()
        
        // Get paths to watch
        let pathsToWatch = await getCustomDescriptionPaths()
        
        // Start watching existing files
        for path in pathsToWatch {
            if FileManager.default.fileExists(atPath: path) && !watchedPaths.contains(path) {
                let watcher = FileWatcher(path: path, delegate: self)
                fileWatchers.append(watcher)
                watchedPaths.insert(path)
                watcher.startWatching()
            }
        }
        
        print("FileWatcher: Setup complete, watching \(fileWatchers.count) files")
    }
    
    private func stopFileWatching() async {
        for watcher in fileWatchers {
            watcher.stopWatching()
        }
        fileWatchers.removeAll()
        watchedPaths.removeAll()
        print("FileWatcher: Stopped all file watchers")
    }
    
    private func getCustomDescriptionPaths() async -> [String] {
        // Return the same paths that loadCustomDescriptions() checks
        let possiblePaths: [URL?] = [
            // 1. User-specific configuration (highest priority)
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".portkiller/descriptions.json"),
            
            // 2. System-wide configuration
            URL(fileURLWithPath: "/usr/local/etc/portkiller/descriptions.json"),
            URL(fileURLWithPath: "/etc/portkiller/descriptions.json"),
            
            // 3. Application bundle (for development/testing)
            Bundle.main.url(forResource: "descriptions", withExtension: "json"),
            
            // 4. Current working directory (for development)
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("descriptions.json")
        ]
        
        return possiblePaths.compactMap { $0?.path }
    }
    
    // Method to get configuration status for debugging/monitoring
    func getConfigurationStatus() async -> ConfigurationStatus {
        if !isLoaded {
            await loadDescriptions()
        }
        
        let currentDatabase = database ?? builtInDatabase
        
        // Check if using custom configuration by comparing counts (since structs can't use identity comparison)
        let isUsingCustom = database != nil && (
            currentDatabase.exactMatches.count != builtInDatabase.exactMatches.count ||
            currentDatabase.patternMatches.count != builtInDatabase.patternMatches.count
        )
        
        return ConfigurationStatus(
            isLoaded: isLoaded,
            isUsingCustomConfiguration: isUsingCustom,
            exactMatchCount: currentDatabase.exactMatches.count,
            patternMatchCount: currentDatabase.patternMatches.count,
            technologyKeywordCount: currentDatabase.technologyKeywords.count,
            actionKeywordCount: currentDatabase.actionKeywords.count,
            namingConventionCount: currentDatabase.namingConventions.count,
            fallbackDescriptionCount: currentDatabase.fallbackDescriptions.count
        )
    }
    
    // Performance monitoring methods
    func getPerformanceMetrics() async -> PerformanceMetrics {
        await updateMemoryUsage()
        return performanceMetrics
    }
    
    // MARK: - Performance Optimization Methods
    
    private func precompilePatterns() async {
        guard let currentDatabase = database else { return }
        
        // Pre-compile pattern matches
        compiledPatternMatches = currentDatabase.patternMatches.compactMap { patternMatch in
            CompiledPatternMatch(from: patternMatch)
        }
        
        // Pre-compile naming conventions
        compiledNamingConventions = currentDatabase.namingConventions.compactMap { convention in
            CompiledPatternMatch(from: convention)
        }
        
        print("Performance optimization: Pre-compiled \(compiledPatternMatches.count) pattern matches and \(compiledNamingConventions.count) naming conventions")
    }
    
    private func initializePerformanceMonitoring() async {
        performanceMetrics = PerformanceMetrics()
        await updateMemoryUsage()
        print("Performance monitoring initialized - Memory usage: \(performanceMetrics.memoryUsageMB) MB")
    }
    
    private func getCachedDescription(for processName: String) async -> CachedDescription? {
        // Check if cache entry exists and is not expired
        if let cached = descriptionCache[processName] {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < cacheExpirationTime {
                // Update access count
                descriptionCache[processName] = cached.withIncrementedAccess()
                return cached
            } else {
                // Remove expired entry
                descriptionCache.removeValue(forKey: processName)
            }
        }
        return nil
    }
    
    private func cacheDescription(for processName: String, description: ProcessDescription) async {
        // Implement LRU cache eviction if cache is full
        if descriptionCache.count >= maxCacheSize {
            await evictLeastRecentlyUsed()
        }
        
        descriptionCache[processName] = CachedDescription(description: description)
        
        // Periodically check memory usage
        let now = Date()
        if now.timeIntervalSince(performanceMetrics.lastMemoryCheck) > memoryCheckInterval {
            await updateMemoryUsage()
        }
    }
    
    private func evictLeastRecentlyUsed() async {
        // Find the least recently used entry (oldest timestamp with lowest access count)
        let sortedEntries = descriptionCache.sorted { (entry1, entry2) in
            if entry1.value.accessCount == entry2.value.accessCount {
                return entry1.value.timestamp < entry2.value.timestamp
            }
            return entry1.value.accessCount < entry2.value.accessCount
        }
        
        // Remove the least recently used entries (remove 10% of cache)
        let entriesToRemove = max(1, maxCacheSize / 10)
        for i in 0..<min(entriesToRemove, sortedEntries.count) {
            descriptionCache.removeValue(forKey: sortedEntries[i].key)
        }
        
        print("Cache eviction: Removed \(entriesToRemove) entries, cache size now: \(descriptionCache.count)")
    }
    
    private func clearCache() async {
        descriptionCache.removeAll()
        performanceMetrics.cacheHits = 0
        performanceMetrics.cacheMisses = 0
        print("Performance optimization: Cache cleared")
    }
    
    private func updatePerformanceMetrics(lookupTime: Double, cacheHit: Bool) async {
        performanceMetrics.lookupCount += 1
        
        if cacheHit {
            performanceMetrics.cacheHits += 1
        } else {
            performanceMetrics.cacheMisses += 1
        }
        
        // Update average lookup time using exponential moving average
        let alpha = 0.1 // Smoothing factor
        performanceMetrics.averageLookupTime = (1 - alpha) * performanceMetrics.averageLookupTime + alpha * lookupTime
    }
    
    private func updateMemoryUsage() async {
        // Estimate memory usage of the service
        var memoryUsage = 0
        
        // Database memory usage
        if let db = database {
            // Estimate memory for exact matches
            for (key, value) in db.exactMatches {
                memoryUsage += key.utf8.count + value.utf8.count + 32 // overhead
            }
            
            // Estimate memory for pattern matches
            for pattern in db.patternMatches {
                memoryUsage += pattern.pattern.utf8.count + pattern.description.utf8.count + pattern.category.utf8.count + 64
            }
            
            // Estimate memory for technology keywords
            for (key, value) in db.technologyKeywords {
                memoryUsage += key.utf8.count + value.utf8.count + 32
            }
            
            // Estimate memory for action keywords
            for (key, value) in db.actionKeywords {
                memoryUsage += key.utf8.count + value.utf8.count + 32
            }
            
            // Estimate memory for naming conventions
            for convention in db.namingConventions {
                memoryUsage += convention.pattern.utf8.count + convention.description.utf8.count + convention.category.utf8.count + 64
            }
            
            // Estimate memory for fallback descriptions
            for (key, value) in db.fallbackDescriptions {
                memoryUsage += key.utf8.count + value.utf8.count + 32
            }
        }
        
        // Cache memory usage
        for (key, cached) in descriptionCache {
            memoryUsage += key.utf8.count + cached.description.text.utf8.count + 64 // overhead for CachedDescription
        }
        
        // Pre-compiled patterns memory usage
        for pattern in compiledPatternMatches {
            memoryUsage += pattern.pattern.utf8.count + pattern.description.utf8.count + pattern.category.utf8.count + 128 // regex overhead
        }
        
        for convention in compiledNamingConventions {
            memoryUsage += convention.pattern.utf8.count + convention.description.utf8.count + convention.category.utf8.count + 128
        }
        
        performanceMetrics.memoryUsageBytes = memoryUsage
        performanceMetrics.lastMemoryCheck = Date()
        
        // Log warning if memory usage is approaching the limit
        let memoryMB = performanceMetrics.memoryUsageMB
        if memoryMB > 0.8 { // 80% of 1MB limit
            print("Warning: Memory usage is \(String(format: "%.2f", memoryMB)) MB (approaching 1MB limit)")
            
            // If we're over the limit, clear some cache
            if memoryMB > 1.0 {
                print("Memory limit exceeded, clearing cache to free memory")
                await clearCache()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCustomDescriptions() async throws -> DescriptionDatabase? {
        // Look for custom description files in priority order
        let possiblePaths: [URL?] = [
            // 1. User-specific configuration (highest priority)
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".portkiller/descriptions.json"),
            
            // 2. System-wide configuration
            URL(fileURLWithPath: "/usr/local/etc/portkiller/descriptions.json"),
            URL(fileURLWithPath: "/etc/portkiller/descriptions.json"),
            
            // 3. Application bundle (for development/testing)
            Bundle.main.url(forResource: "descriptions", withExtension: "json"),
            
            // 4. Current working directory (for development)
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("descriptions.json")
        ]
        
        var loadedDatabases: [DescriptionDatabase] = []
        var loadErrors: [String] = []
        
        for optionalPath in possiblePaths {
            guard let path = optionalPath else { continue }
            
            if FileManager.default.fileExists(atPath: path.path) {
                do {
                    let data = try Data(contentsOf: path)
                    let customDatabase = try validateAndDecodeDatabase(data: data, source: path.path)
                    loadedDatabases.append(customDatabase)
                    print("Successfully loaded custom descriptions from: \(path.path)")
                } catch {
                    let errorMessage = "Failed to load custom descriptions from \(path.path): \(error.localizedDescription)"
                    loadErrors.append(errorMessage)
                    print("Warning: \(errorMessage)")
                    // Continue trying other paths instead of failing completely
                }
            }
        }
        
        // If we have any loaded databases, merge them (later ones take precedence)
        if !loadedDatabases.isEmpty {
            var mergedDatabase = loadedDatabases[0]
            for database in loadedDatabases.dropFirst() {
                mergedDatabase = mergeDescriptions(builtin: mergedDatabase, custom: database)
            }
            return mergedDatabase
        }
        
        // If we had errors but no successful loads, log them
        if !loadErrors.isEmpty {
            print("Custom description loading summary: \(loadErrors.count) errors occurred")
            for error in loadErrors {
                print("  - \(error)")
            }
        }
        
        return nil
    }
    
    private func validateAndDecodeDatabase(data: Data, source: String) throws -> DescriptionDatabase {
        // First, try to decode the JSON
        let decoder = JSONDecoder()
        let database: DescriptionDatabase
        
        do {
            database = try decoder.decode(DescriptionDatabase.self, from: data)
        } catch let decodingError as DecodingError {
            throw ConfigurationError.invalidFormat("Invalid JSON format in \(source): \(decodingError.localizedDescription)")
        } catch {
            throw ConfigurationError.invalidFormat("Failed to decode configuration from \(source): \(error.localizedDescription)")
        }
        
        // Validate the loaded database
        try validateDatabase(database, source: source)
        
        return database
    }
    
    private func validateDatabase(_ database: DescriptionDatabase, source: String) throws {
        var validationErrors: [String] = []
        
        // Validate pattern matches have valid regex patterns
        for (index, patternMatch) in database.patternMatches.enumerated() {
            if patternMatch.compiledRegex == nil {
                validationErrors.append("Invalid regex pattern at index \(index): '\(patternMatch.pattern)'")
            }
            
            if patternMatch.description.isEmpty {
                validationErrors.append("Empty description for pattern at index \(index): '\(patternMatch.pattern)'")
            }
            
            if patternMatch.category.isEmpty {
                validationErrors.append("Empty category for pattern at index \(index): '\(patternMatch.pattern)'")
            }
        }
        
        // Validate naming conventions have valid regex patterns
        for (index, convention) in database.namingConventions.enumerated() {
            if convention.compiledRegex == nil {
                validationErrors.append("Invalid regex pattern in naming convention at index \(index): '\(convention.pattern)'")
            }
            
            if convention.description.isEmpty {
                validationErrors.append("Empty description for naming convention at index \(index): '\(convention.pattern)'")
            }
        }
        
        // Validate that descriptions are not empty
        for (key, value) in database.exactMatches {
            if value.isEmpty {
                validationErrors.append("Empty description for exact match: '\(key)'")
            }
        }
        
        for (key, value) in database.technologyKeywords {
            if value.isEmpty {
                validationErrors.append("Empty description for technology keyword: '\(key)'")
            }
        }
        
        for (key, value) in database.actionKeywords {
            if value.isEmpty {
                validationErrors.append("Empty description for action keyword: '\(key)'")
            }
        }
        
        // Check for reasonable limits to prevent memory issues
        let maxEntries = 10000
        if database.exactMatches.count > maxEntries {
            validationErrors.append("Too many exact matches (\(database.exactMatches.count) > \(maxEntries))")
        }
        
        if database.patternMatches.count > 1000 {
            validationErrors.append("Too many pattern matches (\(database.patternMatches.count) > 1000)")
        }
        
        // If there are validation errors, decide whether to fail or warn
        if !validationErrors.isEmpty {
            let errorMessage = "Configuration validation errors in \(source):\n" + validationErrors.joined(separator: "\n")
            
            // For now, we'll log warnings but not fail completely
            // This allows the system to continue with partial configurations
            print("Warning: \(errorMessage)")
            
            // Only fail if there are critical errors (like all patterns being invalid)
            let criticalErrors = validationErrors.filter { $0.contains("Invalid regex pattern") }
            if criticalErrors.count == database.patternMatches.count + database.namingConventions.count && 
               (database.patternMatches.count > 0 || database.namingConventions.count > 0) {
                throw ConfigurationError.validationFailed("Critical validation errors: all regex patterns are invalid")
            }
        }
    }
    
    nonisolated func mergeDescriptions(builtin: DescriptionDatabase, custom: DescriptionDatabase) -> DescriptionDatabase {
        // Custom descriptions take precedence over built-in ones
        
        // Merge exact matches - custom overrides built-in
        var mergedExactMatches = builtin.exactMatches
        for (key, value) in custom.exactMatches {
            if !value.isEmpty { // Only override with non-empty values
                mergedExactMatches[key] = value
            }
        }
        
        // Merge pattern matches - custom patterns are checked first (prepend instead of append)
        var mergedPatternMatches = custom.patternMatches.filter { !$0.description.isEmpty }
        mergedPatternMatches.append(contentsOf: builtin.patternMatches)
        
        // Merge technology keywords - custom overrides built-in
        var mergedTechnologyKeywords = builtin.technologyKeywords
        for (key, value) in custom.technologyKeywords {
            if !value.isEmpty { // Only override with non-empty values
                mergedTechnologyKeywords[key] = value
            }
        }
        
        // Merge action keywords - custom overrides built-in
        var mergedActionKeywords = builtin.actionKeywords
        for (key, value) in custom.actionKeywords {
            if !value.isEmpty { // Only override with non-empty values
                mergedActionKeywords[key] = value
            }
        }
        
        // Merge naming conventions - custom conventions are checked first (prepend)
        var mergedNamingConventions = custom.namingConventions.filter { !$0.description.isEmpty }
        mergedNamingConventions.append(contentsOf: builtin.namingConventions)
        
        // Merge fallback descriptions - custom overrides built-in
        var mergedFallbackDescriptions = builtin.fallbackDescriptions
        for (key, value) in custom.fallbackDescriptions {
            if !value.isEmpty { // Only override with non-empty values
                mergedFallbackDescriptions[key] = value
            }
        }
        
        let mergedDatabase = DescriptionDatabase(
            exactMatches: mergedExactMatches,
            patternMatches: mergedPatternMatches,
            technologyKeywords: mergedTechnologyKeywords,
            actionKeywords: mergedActionKeywords,
            namingConventions: mergedNamingConventions,
            fallbackDescriptions: mergedFallbackDescriptions
        )
        
        // Log merge statistics
        let customOverrides = custom.exactMatches.keys.filter { builtin.exactMatches.keys.contains($0) }.count
        let newCustomEntries = custom.exactMatches.count - customOverrides
        
        print("Description database merge complete:")
        print("  - Built-in exact matches: \(builtin.exactMatches.count)")
        print("  - Custom overrides: \(customOverrides)")
        print("  - New custom entries: \(newCustomEntries)")
        print("  - Total exact matches: \(mergedDatabase.exactMatches.count)")
        print("  - Total pattern matches: \(mergedDatabase.patternMatches.count)")
        
        return mergedDatabase
    }
    
    private func inferCategory(from processName: String, description: String? = nil) -> ProcessCategory {
        let name = processName.lowercased()
        let desc = description?.lowercased() ?? ""
        
        // Database services - check first for database-specific processes
        if name.contains("mysql") || name.contains("postgres") || name.contains("mongo") ||
           name.contains("redis") || name.contains("elasticsearch") || name.contains("kibana") ||
           name.contains("memcached") || desc.contains("database") || desc.contains("cache") ||
           desc.contains("search") || desc.contains("analytics") {
            return .database
        }
        
        // System services - check first for macOS system processes and specific system tools
        if (name.hasSuffix("d") && !name.contains("httpd") && !name.contains("lighttpd")) || 
           name.contains("daemon") || name.contains("launchd") ||
           name.contains("kernel") || name.contains("windowserver") || name.contains("finder") ||
           name.contains("dock") || name.contains("bluetooth") || name.contains("wifi") ||
           name.contains("network") || name.contains("syslog") || name.contains("docker") ||
           name.contains("kubernetes") || name.contains("kubectl") || name.contains("systemd") ||
           name.contains("systemuiserver") || name.contains("mds") || name.contains("mdworker") ||
           name.contains("coreaudiod") || name.contains("cfprefsd") || name.contains("loginwindow") ||
           (desc.contains("daemon") && !desc.contains("server")) || 
           (desc.contains("system") && !desc.contains("version control")) || desc.contains("macos") || 
           desc.contains("container") || desc.contains("orchestration") || desc.contains("command-line tool") ||
           desc.contains("metadata") || desc.contains("spotlight") {
            return .system
        }
        
        // Web servers - check for specific web server processes (after system check)
        if name.contains("nginx") || name.contains("apache") || name.contains("httpd") ||
           name.contains("caddy") || name.contains("lighttpd") || name.contains("php") ||
           name.contains("tomcat") || name.contains("jetty") ||
           desc.contains("web server") || desc.contains("http server") || desc.contains("proxy") {
            return .webServer
        }
        
        // Development tools - check both name and description (but exclude docker/kubernetes)
        if (name.contains("dev") || name.contains("webpack") || name.contains("nodemon") ||
           name.contains("rails") || name.contains("vite") || name.contains("parcel") ||
           name.contains("rollup") || name.contains("gulp") || name.contains("grunt") ||
           name.contains("yarn") || name.contains("npm") || name.contains("pnpm") ||
           name.contains("node") || name.contains("python") || name.contains("java") ||
           name.contains("ruby") || name.contains("code") || name.contains("xcode") ||
           name.contains("git") || name.contains("svn") || name.contains("hg") ||
           desc.contains("development") || desc.contains("build") || desc.contains("bundler") ||
           desc.contains("package manager") || desc.contains("interpreter") || desc.contains("runtime") ||
           desc.contains("ide") || desc.contains("version control")) &&
           !name.contains("docker") && !name.contains("kubernetes") {
            return .development
        }
        
        return .other
    }
    
    private enum KeywordType {
        case technology
        case action
    }
    
    private func inferCategoryFromKeyword(_ keyword: String, type: KeywordType) -> ProcessCategory {
        let lowercaseKeyword = keyword.lowercased()
        
        switch type {
        case .technology:
            // Technology-based category inference
            if ["mysql", "postgres", "postgresql", "redis", "mongo", "mongodb", "elasticsearch", "kibana"].contains(lowercaseKeyword) {
                return .database
            } else if ["nginx", "apache", "express", "flask", "django", "rails", "spring", "tomcat", "jetty", "php"].contains(lowercaseKeyword) {
                return .webServer
            } else if ["webpack", "vite", "parcel", "rollup", "gulp", "grunt", "yarn", "npm", "pnpm", "react", "vue", "angular", "python", "java", "node", "nodejs", "ruby", "go", "rust", "dotnet"].contains(lowercaseKeyword) {
                return .development
            } else if ["docker", "kubernetes", "k8s"].contains(lowercaseKeyword) {
                return .system
            }
            
        case .action:
            // Action-based category inference
            if ["server", "api", "web", "proxy", "gateway"].contains(lowercaseKeyword) {
                return .webServer
            } else if ["db", "cache", "queue"].contains(lowercaseKeyword) {
                return .database
            } else if ["dev", "build", "test"].contains(lowercaseKeyword) {
                return .development
            } else if ["daemon", "worker", "monitor", "scheduler", "logger", "auth", "sync", "backup", "deploy", "prod", "staging"].contains(lowercaseKeyword) {
                return .system
            }
        }
        
        return .other
    }
    
    private func generateIntelligentFallback(for processName: String, database: DescriptionDatabase) -> (String, ProcessCategory) {
        let name = processName.lowercased()
        
        // Analyze process name for intelligent patterns
        var hints: [String] = []
        var category: ProcessCategory = .other
        
        // Check for file extensions or language indicators
        if name.contains(".py") || name.contains("python") {
            hints.append("Python")
            category = .development
        } else if name.contains(".js") || name.contains("node") || name.contains("npm") {
            hints.append("JavaScript/Node.js")
            category = .development
        } else if name.contains(".rb") || name.contains("ruby") {
            hints.append("Ruby")
            category = .development
        } else if name.contains(".php") {
            hints.append("PHP")
            category = .webServer
        } else if name.contains(".go") {
            hints.append("Go")
            category = .development
        } else if name.contains(".rs") {
            hints.append("Rust")
            category = .development
        }
        
        // Check for common port-related patterns
        if name.contains("port") || name.contains("listen") || name.contains("bind") {
            hints.append("network service")
            if category == .other { category = .webServer }
        }
        
        // Check for process ID patterns
        if name.contains("pid") || name.matches(regex: ".*\\d+$") {
            hints.append("process instance")
        }
        
        // Check for path-like patterns
        if name.contains("/") || name.contains("\\") {
            hints.append("executable")
            // Try to extract meaningful part from path
            let pathComponents = name.components(separatedBy: CharacterSet(charactersIn: "/\\"))
            if let lastComponent = pathComponents.last, !lastComponent.isEmpty {
                hints.append("(\(lastComponent))")
            }
        }
        
        // Check for version patterns
        if name.matches(regex: ".*v?\\d+\\.\\d+") {
            hints.append("versioned application")
        }
        
        // Check for common suffixes that indicate function
        if name.hasSuffix("_server") || name.hasSuffix("-server") {
            hints.append("server")
            category = .webServer
        } else if name.hasSuffix("_client") || name.hasSuffix("-client") {
            hints.append("client")
        } else if name.hasSuffix("_worker") || name.hasSuffix("-worker") {
            hints.append("worker process")
            category = .system
        } else if name.hasSuffix("_daemon") || name.hasSuffix("-daemon") {
            hints.append("daemon")
            category = .system
        }
        
        // Generate intelligent description
        let baseDescription: String
        if hints.isEmpty {
            // Truly unknown process - provide helpful generic description
            baseDescription = "Unknown application or service"
        } else {
            baseDescription = hints.joined(separator: " ")
        }
        
        // Add safety warning for unknown processes
        let safetyNote = "(exercise caution when terminating)"
        let finalDescription = hints.isEmpty ? 
            "\(baseDescription) \(safetyNote)" : 
            "\(baseDescription.capitalized) \(safetyNote)"
        
        // Use fallback description from database if available
        let fallbackText = database.fallbackDescriptions[category.rawValue] ?? finalDescription
        
        return (fallbackText, category)
    }
}