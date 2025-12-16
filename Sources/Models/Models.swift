import Foundation

struct PortInfo: Identifiable, Hashable, Sendable {
    let id = UUID()
    let port: Int
    let pid: Int
    let processName: String
    let address: String
    let description: ProcessDescription?

    var displayPort: String { ":\(port)" }
    
    init(port: Int, pid: Int, processName: String, address: String, description: ProcessDescription? = nil) {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.address = address
        self.description = description
    }
}

struct WatchedPort: Identifiable, Codable {
    let id: UUID
    let port: Int
    var notifyOnStart: Bool
    var notifyOnStop: Bool

    init(port: Int, notifyOnStart: Bool = true, notifyOnStop: Bool = true) {
        self.id = UUID()
        self.port = port
        self.notifyOnStart = notifyOnStart
        self.notifyOnStop = notifyOnStop
    }
}

// MARK: - Process Description Models

struct ProcessDescription: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    let text: String
    let category: ProcessCategory
    let confidence: DescriptionConfidence
    
    init(text: String, category: ProcessCategory, confidence: DescriptionConfidence) {
        self.id = UUID()
        self.text = text
        self.category = category
        self.confidence = confidence
    }
}

enum ProcessCategory: String, CaseIterable, Codable, Sendable {
    case development = "development"
    case system = "system"
    case database = "database"
    case webServer = "webServer"
    case other = "other"
    
    var fallbackDescription: String {
        switch self {
        case .development:
            return "Development tool or server"
        case .system:
            return "System service or daemon"
        case .database:
            return "Database server"
        case .webServer:
            return "Web server or HTTP service"
        case .other:
            return "Application or service"
        }
    }
}

enum DescriptionConfidence: String, CaseIterable, Codable, Sendable {
    case exact = "exact"
    case pattern = "pattern"
    case fallback = "fallback"
}

// MARK: - Description Utilities

/// Truncates a description text to fit within the specified maximum width
/// - Parameters:
///   - text: The original description text
///   - maxWidth: Maximum number of characters allowed
/// - Returns: Truncated text with ellipsis if needed, or original text if it fits
func truncateDescription(_ text: String, maxWidth: Int) -> String {
    guard maxWidth > 0 else { return text }
    
    // If text fits within limit, return as-is
    if text.count <= maxWidth {
        return text
    }
    
    // Need to truncate - reserve 3 characters for ellipsis
    let ellipsis = "..."
    let availableWidth = maxWidth - ellipsis.count
    
    // If maxWidth is too small to accommodate ellipsis, just truncate without ellipsis
    guard availableWidth > 0 else {
        return String(text.prefix(maxWidth))
    }
    
    // Try to break at word boundary if possible
    let truncatedText = String(text.prefix(availableWidth))
    
    // Look for the last space to break at word boundary
    if let lastSpaceIndex = truncatedText.lastIndex(of: " ") {
        let wordBoundaryText = String(truncatedText[..<lastSpaceIndex])
        // Only use word boundary if it gives us reasonable content (at least 1/3 of available width)
        if wordBoundaryText.count >= availableWidth / 3 {
            return wordBoundaryText + ellipsis
        }
    }
    
    // Fall back to character boundary
    return truncatedText + ellipsis
}
