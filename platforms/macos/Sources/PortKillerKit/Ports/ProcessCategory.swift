import Foundation

public enum ProcessCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case webServer = "Web Server"
    case database = "Database"
    case development = "Development"
    case system = "System"
    case other = "Other"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .webServer: "globe"
        case .database: "cylinder.split.1x2"
        case .development: "hammer"
        case .system: "gearshape"
        case .other: "powerplug"
        }
    }

    private static let rules: [(ProcessCategory, exact: Set<String>, prefixes: [String])] = [
        (.webServer, [], ["nginx", "apache", "httpd", "caddy", "traefik", "lighttpd", "haproxy", "envoy"]),
        (.database, [], ["postgres", "mysql", "mariadb", "redis", "mongo", "sqlite", "cockroach", "clickhouse", "memcached", "valkey", "elasticsearch", "opensearch", "rabbitmq", "kafka"]),
        (.development, ["go", "bun", "php", "npm", "npx", "deno", "java", "ruby", "rails", "puma", "next", "nuxt", "vite", "air"], [
            "node", "pnpm", "yarn", "python", "cargo", "swift", "webpack", "esbuild", "remix", "gunicorn", "uvicorn",
            "dotnet", "turbo", "astro", "rollup", "parcel", "flask", "django", "beam", "elixir", "dart", "flutter", "gradle", "kotlin",
        ]),
        (.system, ["mds"], ["launchd", "rapportd", "sharingd", "airplay", "control", "kernel", "spotlight", "mdns", "configd", "identityservicesd"]),
    ]

    public static func detect(_ processName: String) -> ProcessCategory {
        let tokens = processName.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for (category, exact, prefixes) in rules {
            if tokens.contains(where: { token in exact.contains(token) || prefixes.contains { token.hasPrefix($0) } }) {
                return category
            }
        }
        return .other
    }
}
