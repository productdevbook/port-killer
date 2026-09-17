public import Foundation

public struct CommandLineTool: Sendable, Hashable, Identifiable {
    public var name: String
    public var formula: String
    public var isRequired: Bool

    public var id: String { name }

    public static let kubectl = CommandLineTool(name: "kubectl", formula: "kubernetes-cli", isRequired: true)
    public static let socat = CommandLineTool(name: "socat", formula: "socat", isRequired: false)
    public static let cloudflared = CommandLineTool(name: "cloudflared", formula: "cloudflared", isRequired: true)
    public static let brew = CommandLineTool(name: "brew", formula: "", isRequired: false)

    public var searchDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var directories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/opt/local/bin",
            "\(home)/.local/bin",
            "\(home)/bin",
        ]
        if name == "kubectl" {
            directories += [
                "\(home)/.rd/bin",
                "\(home)/.orbstack/bin",
                "/Applications/Docker.app/Contents/Resources/bin",
            ]
        }
        return directories
    }

    public func locate(customPath: String? = nil) -> URL? {
        if let customPath = customPath?.trimmingCharacters(in: .whitespaces), !customPath.isEmpty {
            let expanded = (customPath as NSString).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: expanded) ? URL(filePath: expanded) : nil
        }
        return searchDirectories
            .map { URL(filePath: $0).appending(path: name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public var installCommand: String {
        "brew install \(formula)"
    }

    public static var searchPath: String {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen: Set<String> = []
        return (kubectl.searchDirectories + inherited + ["/bin", "/usr/sbin", "/sbin"])
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
    }
}
