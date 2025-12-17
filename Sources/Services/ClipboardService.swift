import AppKit

/// Utility service for clipboard operations
enum ClipboardService {
    /// Copy text to clipboard
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Copy logs as markdown formatted text
    static func copyLogsAsMarkdown(_ logs: [PortForwardLogEntry], connectionName: String? = nil) {
        var markdown = ""

        if let name = connectionName {
            markdown += "# Logs: \(name)\n\n"
        }

        markdown += "```\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"

        for log in logs {
            let timestamp = dateFormatter.string(from: log.timestamp)
            let source = log.type == .portForward ? "kubectl" : "socat"
            let prefix = log.isError ? "[ERROR]" : ""
            markdown += "\(timestamp) [\(source)] \(prefix)\(log.message)\n"
        }
        markdown += "```\n"

        copy(markdown)
    }

    /// Copy any items as markdown list
    static func copyAsMarkdownList(_ items: [String], title: String? = nil) {
        var markdown = ""

        if let title = title {
            markdown += "# \(title)\n\n"
        }

        for item in items {
            markdown += "- \(item)\n"
        }

        copy(markdown)
    }

    /// Copy as markdown code block
    static func copyAsCodeBlock(_ text: String, language: String = "") {
        let markdown = "```\(language)\n\(text)\n```"
        copy(markdown)
    }

    /// Copy as markdown table
    static func copyAsMarkdownTable(headers: [String], rows: [[String]]) {
        var markdown = ""

        // Header row
        markdown += "| " + headers.joined(separator: " | ") + " |\n"

        // Separator row
        markdown += "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |\n"

        // Data rows
        for row in rows {
            markdown += "| " + row.joined(separator: " | ") + " |\n"
        }

        copy(markdown)
    }
}
