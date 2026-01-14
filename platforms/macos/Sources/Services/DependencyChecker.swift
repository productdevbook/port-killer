import Foundation
import Defaults

// MARK: - Dependency

struct PortForwardDependency: Sendable {
    let name: String
    let possiblePaths: [String]
    let brewPackage: String
    let isRequired: Bool

    var isInstalled: Bool {
        possiblePaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    var installedPath: String? {
        possiblePaths.first { FileManager.default.fileExists(atPath: $0) }
    }
}

// MARK: - Dependency Checker

actor DependencyChecker {
    static let shared = DependencyChecker()

    nonisolated let dependencies: [PortForwardDependency] = [
        PortForwardDependency(
            name: "kubectl",
            possiblePaths: [
                "/opt/homebrew/bin/kubectl",
                "/usr/local/bin/kubectl",
                "/usr/bin/kubectl"
            ],
            brewPackage: "kubernetes-cli",
            isRequired: true
        ),
        PortForwardDependency(
            name: "socat",
            possiblePaths: [
                "/opt/homebrew/bin/socat",
                "/usr/local/bin/socat"
            ],
            brewPackage: "socat",
            isRequired: false
        )
    ]

    nonisolated var kubectl: PortForwardDependency {
        dependencies.first { $0.name == "kubectl" }!
    }

    nonisolated var socat: PortForwardDependency {
        dependencies.first { $0.name == "socat" }!
    }

    nonisolated var missingRequired: [PortForwardDependency] {
        dependencies.filter { $0.isRequired && !$0.isInstalled }
    }

    nonisolated var missingOptional: [PortForwardDependency] {
        dependencies.filter { !$0.isRequired && !$0.isInstalled }
    }

    nonisolated var allRequiredInstalled: Bool {
        missingRequired.isEmpty
    }

    nonisolated var kubectlPath: String? {
        // Check custom path first
        if let custom = Defaults[.customKubectlPath],
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return custom
        }
        return kubectl.installedPath
    }

    nonisolated var socatPath: String? {
        // Check custom path first
        if let custom = Defaults[.customSocatPath],
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return custom
        }
        return socat.installedPath
    }

    nonisolated var isUsingCustomKubectl: Bool {
        if let custom = Defaults[.customKubectlPath],
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return true
        }
        return false
    }

    nonisolated var isUsingCustomSocat: Bool {
        if let custom = Defaults[.customSocatPath],
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return true
        }
        return false
    }

    func checkAndInstallMissing() async -> (success: Bool, message: String) {
        let missing = dependencies.filter { !$0.isInstalled }

        guard !missing.isEmpty else {
            return (true, "All dependencies are installed")
        }

        let brewPath: String
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            brewPath = "/opt/homebrew/bin/brew"
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/brew") {
            brewPath = "/usr/local/bin/brew"
        } else {
            return (false, "Homebrew is not installed. Please install it from https://brew.sh")
        }

        var results: [String] = []

        for dep in missing {
            let result = await installWithBrew(brewPath: brewPath, package: dep.brewPackage)
            results.append("\(dep.name): \(result.success ? "Installed" : "Failed - \(result.message)")")
        }

        let allSuccess = missing.allSatisfy(\.isInstalled)
        return (allSuccess, results.joined(separator: "\n"))
    }

    private func installWithBrew(brewPath: String, package: String) async -> (success: Bool, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["install", package]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return process.terminationStatus == 0 ? (true, "Installed") : (false, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
