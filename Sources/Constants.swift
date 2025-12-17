import Foundation

enum AppInfo {
    static let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
    }()

    static let build: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }()

    static let versionString: String = {
        "v\(version) (\(build))"
    }()

    static let githubRepo = "https://github.com/productdevbook/port-killer"
    static let githubReleases = "https://github.com/productdevbook/port-killer/releases"
    static let githubSponsors = "https://github.com/sponsors/productdevbook"
    static let githubIssues = "https://github.com/productdevbook/port-killer/issues"
    static let twitterURL = "https://x.com/productdevbook"
}
