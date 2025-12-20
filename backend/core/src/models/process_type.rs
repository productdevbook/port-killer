//! Process type categorization based on process names.

use serde::{Deserialize, Serialize};

/// Category of process based on its function.
///
/// ProcessType provides automatic detection of process categories based on
/// well-known process names, enabling better organization and visualization.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[derive(Default)]
pub enum ProcessType {
    /// Web servers (nginx, apache, caddy, etc.)
    WebServer,
    /// Database servers (postgres, mysql, redis, etc.)
    Database,
    /// Development tools (node, python, vite, etc.)
    Development,
    /// System processes (launchd, kernel services, etc.)
    System,
    /// Other/unknown processes
    #[default]
    Other,
}

impl ProcessType {
    /// All available process types.
    pub const ALL: [ProcessType; 5] = [
        ProcessType::WebServer,
        ProcessType::Database,
        ProcessType::Development,
        ProcessType::System,
        ProcessType::Other,
    ];

    /// Detect the process type from a process name.
    ///
    /// Analyzes the process name against known patterns to categorize it into
    /// one of the predefined process types. The detection is case-insensitive.
    ///
    /// # Examples
    /// ```
    /// use portkiller_core::ProcessType;
    ///
    /// assert_eq!(ProcessType::detect("nginx"), ProcessType::WebServer);
    /// assert_eq!(ProcessType::detect("postgres"), ProcessType::Database);
    /// assert_eq!(ProcessType::detect("node"), ProcessType::Development);
    /// assert_eq!(ProcessType::detect("launchd"), ProcessType::System);
    /// assert_eq!(ProcessType::detect("unknown"), ProcessType::Other);
    /// ```
    pub fn detect(process_name: &str) -> Self {
        let name = process_name.to_lowercase();

        // Web servers
        const WEB_SERVERS: &[&str] = &[
            "nginx", "apache", "httpd", "caddy", "traefik", "lighttpd", "envoy",
        ];
        if WEB_SERVERS.iter().any(|s| name.contains(s)) {
            return ProcessType::WebServer;
        }

        // Databases
        const DATABASES: &[&str] = &[
            "postgres",
            "mysql",
            "mariadb",
            "redis",
            "mongo",
            "sqlite",
            "cockroach",
            "clickhouse",
            "cassandra",
            "elasticsearch",
            "memcached",
        ];
        if DATABASES.iter().any(|s| name.contains(s)) {
            return ProcessType::Database;
        }

        // Development tools
        const DEV_TOOLS: &[&str] = &[
            "node", "npm", "yarn", "pnpm", "bun", "deno", "python", "ruby", "php", "java", "go",
            "cargo", "rustc", "swift", "vite", "webpack", "esbuild", "next", "nuxt", "remix",
            "astro", "turbo", "parcel",
        ];
        if DEV_TOOLS.iter().any(|s| name.contains(s)) {
            return ProcessType::Development;
        }

        // System processes
        const SYSTEM_PROCS: &[&str] = &[
            "launchd",
            "rapportd",
            "sharingd",
            "airplay",
            "control",
            "kernel",
            "mds",
            "spotlight",
            "systemd",
            "init",
            "dbus",
            "udev",
        ];
        if SYSTEM_PROCS.iter().any(|s| name.contains(s)) {
            return ProcessType::System;
        }

        ProcessType::Other
    }

    /// Get the display name for this process type.
    pub fn display_name(&self) -> &'static str {
        match self {
            ProcessType::WebServer => "Web Server",
            ProcessType::Database => "Database",
            ProcessType::Development => "Development",
            ProcessType::System => "System",
            ProcessType::Other => "Other",
        }
    }

    /// Get an icon identifier for this process type.
    /// These correspond to SF Symbols on macOS.
    pub fn icon(&self) -> &'static str {
        match self {
            ProcessType::WebServer => "globe",
            ProcessType::Database => "cylinder",
            ProcessType::Development => "hammer",
            ProcessType::System => "gearshape",
            ProcessType::Other => "powerplug",
        }
    }
}

impl std::fmt::Display for ProcessType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.display_name())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_web_servers() {
        assert_eq!(ProcessType::detect("nginx"), ProcessType::WebServer);
        assert_eq!(ProcessType::detect("apache2"), ProcessType::WebServer);
        assert_eq!(ProcessType::detect("caddy"), ProcessType::WebServer);
    }

    #[test]
    fn test_detect_databases() {
        assert_eq!(ProcessType::detect("postgres"), ProcessType::Database);
        assert_eq!(ProcessType::detect("mysqld"), ProcessType::Database);
        assert_eq!(ProcessType::detect("redis-server"), ProcessType::Database);
    }

    #[test]
    fn test_detect_development() {
        assert_eq!(ProcessType::detect("node"), ProcessType::Development);
        assert_eq!(ProcessType::detect("python3"), ProcessType::Development);
        assert_eq!(ProcessType::detect("vite"), ProcessType::Development);
    }

    #[test]
    fn test_detect_system() {
        assert_eq!(ProcessType::detect("launchd"), ProcessType::System);
        assert_eq!(ProcessType::detect("systemd"), ProcessType::System);
    }

    #[test]
    fn test_detect_other() {
        assert_eq!(ProcessType::detect("unknown_app"), ProcessType::Other);
        assert_eq!(ProcessType::detect("my_custom_server"), ProcessType::Other);
    }

    #[test]
    fn test_case_insensitive() {
        assert_eq!(ProcessType::detect("NGINX"), ProcessType::WebServer);
        assert_eq!(ProcessType::detect("PostgreSQL"), ProcessType::Database);
    }
}
