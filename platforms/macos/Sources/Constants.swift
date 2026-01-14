import Foundation

// MARK: - App Information

/**
 * AppInfo provides application metadata and external links.
 */
enum AppInfo {
    /// Application version from bundle info (e.g., "1.3.0")
    static let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
    }()

    /// Build number from bundle info (e.g., "42")
    static let build: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }()

    /// Formatted version string (e.g., "v1.3.0 (42)")
    static let versionString: String = {
        "v\(version) (\(build))"
    }()

    /// GitHub repository URL
    static let githubRepo = "https://github.com/productdevbook/port-killer"

    /// GitHub releases page URL
    static let githubReleases = "https://github.com/productdevbook/port-killer/releases"

    /// GitHub sponsors page URL
    static let githubSponsors = "https://github.com/sponsors/productdevbook"

    /// GitHub issues page URL
    static let githubIssues = "https://github.com/productdevbook/port-killer/issues"

    /// Twitter/X profile URL
    static let twitterURL = "https://x.com/productdevbook"
}

// MARK: - Application Constants

/**
 * AppConstants defines core application configuration values.
 */
enum AppConstants {
    /// Default refresh interval in seconds
    static let defaultRefreshInterval: Int = 5

    /// Grace period between SIGTERM and SIGKILL when killing processes
    static let killGracePeriod: Duration = .milliseconds(500)

    /// Maximum length for displayed command strings
    static let maxCommandLength: Int = 200

    /// How long to cache sponsor data before refreshing (1 day)
    static let sponsorCacheExpiry: TimeInterval = 86400
}

// MARK: - UI Constants

/**
 * UIConstants defines size and layout constants for UI components.
 */
enum UIConstants {
    /**
     * Menu bar view dimensions
     */
    enum MenuBar {
        /// Fixed width of menu bar popover
        static let width: CGFloat = 340

        /// Maximum height of menu bar popover
        static let maxHeight: CGFloat = 400

        /// Height of each port row
        static let rowHeight: CGFloat = 44
    }

    /**
     * Main window dimensions
     */
    enum MainWindow {
        /// Minimum window width
        static let minWidth: CGFloat = 800

        /// Minimum window height
        static let minHeight: CGFloat = 500
    }
}
