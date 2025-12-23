using System;
using System.Linq;

namespace PortKiller.Models;

/// <summary>
/// Category of process based on its function.
/// Provides automatic detection of process categories based on well-known process names.
/// </summary>
public enum ProcessType
{
    WebServer,
    Database,
    Development,
    System,
    Other
}

public static class ProcessTypeExtensions
{
    /// <summary>
    /// Gets the display name for the process type
    /// </summary>
    public static string GetDisplayName(this ProcessType type) => type switch
    {
        ProcessType.WebServer => "Web Server",
        ProcessType.Database => "Database",
        ProcessType.Development => "Development",
        ProcessType.System => "System",
        ProcessType.Other => "Other",
        _ => "Other"
    };

    /// <summary>
    /// Gets the icon glyph (Segoe Fluent Icons) for the process type
    /// </summary>
    public static string GetIcon(this ProcessType type) => type switch
    {
        ProcessType.WebServer => "\uE774", // Globe
        ProcessType.Database => "\uF1AA", // Database
        ProcessType.Development => "\uE90F", // Code
        ProcessType.System => "\uE713", // Settings
        ProcessType.Other => "\uE7E8", // Plug
        _ => "\uE7E8"
    };

    /// <summary>
    /// Detect the process type from a process name
    /// </summary>
    public static ProcessType Detect(string processName)
    {
        if (string.IsNullOrEmpty(processName))
            return ProcessType.Other;

        var name = processName.ToLowerInvariant();

        // Web servers
        string[] webServers = ["nginx", "apache", "httpd", "caddy", "traefik", "lighttpd", "iis", "iisexpress"];
        if (webServers.Any(name.Contains))
            return ProcessType.WebServer;

        // Databases
        string[] databases = ["postgres", "mysql", "mariadb", "redis", "mongo", "sqlite", "cockroach", "clickhouse", "sqlservr", "mssql"];
        if (databases.Any(name.Contains))
            return ProcessType.Database;

        // Development tools
        string[] devTools = ["node", "npm", "yarn", "python", "ruby", "php", "java", "go", "cargo", "dotnet", "vite", "webpack", "esbuild", "next", "nuxt", "remix", "bun", "deno"];
        if (devTools.Any(name.Contains))
            return ProcessType.Development;

        // System processes
        string[] systemProcs = ["svchost", "csrss", "lsass", "winlogon", "services", "system", "smss", "dwm"];
        if (systemProcs.Any(name.Contains))
            return ProcessType.System;

        return ProcessType.Other;
    }
}
