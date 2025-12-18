import SwiftUI

struct CloudflaredMissingBanner: View {
    @Environment(AppState.self) private var appState
    @State private var isCopied = false
    @State private var isInstalling = false
    @State private var installError: String?

    private let installCommand = "brew install cloudflared"

    /// Check if Homebrew is installed
    private var brewPath: String? {
        let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private var isBrewInstalled: Bool {
        brewPath != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("cloudflared Required")
                        .font(.headline)
                    if !isBrewInstalled {
                        Text("Homebrew is required. Visit brew.sh to install.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Install cloudflared to share ports via Cloudflare Tunnel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Refresh button to re-check installation
                Button {
                    appState.tunnelManager.recheckInstallation()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Check if installed")

                if isBrewInstalled {
                    // Copy command button
                    Button {
                        ClipboardService.copy(installCommand)
                        isCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            isCopied = false
                        }
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .help(isCopied ? "Copied!" : "Copy command")

                    // Install button
                    Button {
                        installCloudflared()
                    } label: {
                        if isInstalling {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                            Text("Installing...")
                        } else {
                            Label("Install", systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)
                } else {
                    // Open brew.sh button
                    Button {
                        if let url = URL(string: "https://brew.sh") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Get Homebrew", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)

            // Error message
            if let error = installError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        installError = nil
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Color.blue.opacity(0.1))
        .overlay(
            Rectangle()
                .fill(Color.blue)
                .frame(height: 2),
            alignment: .top
        )
    }

    private func installCloudflared() {
        guard let brewPath = brewPath else { return }

        isInstalling = true
        installError = nil

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["install", "cloudflared"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                await MainActor.run {
                    isInstalling = false
                    if process.terminationStatus == 0 {
                        appState.tunnelManager.recheckInstallation()
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                        installError = "Installation failed: \(output.prefix(100))"
                    }
                }
            } catch {
                await MainActor.run {
                    isInstalling = false
                    installError = "Failed to run brew: \(error.localizedDescription)"
                }
            }
        }
    }
}
