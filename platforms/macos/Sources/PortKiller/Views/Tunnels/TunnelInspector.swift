import PortKillerKit
import SwiftUI

struct TunnelInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.tunnels.selection {
        case .quick(let id):
            if let tunnel = model.tunnels.quickTunnels.first(where: { $0.id == id }) {
                QuickTunnelDetails(tunnel: tunnel)
                    .id(id)
            } else {
                empty
            }
        case .named(let id):
            if let tunnel = model.tunnels.namedTunnels.first(where: { $0.id == id }) {
                NamedTunnelDetails(tunnel: tunnel)
                    .id(id)
            } else {
                empty
            }
        case nil:
            empty
        }
    }

    private var empty: some View {
        ContentUnavailableView("No Tunnel Selected", systemImage: "cloud", description: Text("Select a tunnel to see its routes, connections and logs."))
    }
}

private enum TunnelPage: String, CaseIterable {
    case details = "Details"
    case logs = "Logs"
}

private struct QuickTunnelDetails: View {
    @Environment(AppModel.self) private var model
    let tunnel: QuickTunnel
    @State private var page = TunnelPage.details

    var body: some View {
        VStack(spacing: 0) {
            InspectorSegmentedPicker(selection: $page, options: TunnelPage.allCases) { $0 == .logs && !tunnel.logs.isEmpty ? "Logs (\(tunnel.logs.count))" : $0.rawValue }
            switch page {
            case .details:
                Form {
                    Section {
                        QuickTunnelSummary(tunnel: tunnel)
                    }
                    Section("Details") {
                        LabeledContent {
                            Text(String(tunnel.port))
                                .monospacedDigit()
                        } label: {
                            Label("Local Port", systemImage: "laptopcomputer")
                        }
                        if let startedAt = tunnel.startedAt {
                            LabeledContent {
                                Text(startedAt, format: .relative(presentation: .named))
                            } label: {
                                Label("Started", systemImage: "clock")
                            }
                        }
                        LabeledContent {
                            Text(model.preferences.quickTunnelProtocol.title)
                        } label: {
                            Label("Protocol", systemImage: "network")
                        }
                    }
                }
                .formStyle(.grouped)
            case .logs:
                LogConsole(lines: tunnel.logs.map(\.consoleLine), emptyText: "cloudflared output appears here.", onClear: { tunnel.clearLogs() })
            }
        }
    }
}

private struct NamedTunnelDetails: View {
    @Environment(AppModel.self) private var model
    let tunnel: NamedTunnel
    @State private var page = TunnelPage.details

    var body: some View {
        VStack(spacing: 0) {
            InspectorSegmentedPicker(selection: $page, options: TunnelPage.allCases) { $0 == .logs && !tunnel.logs.isEmpty ? "Logs (\(tunnel.logs.count))" : $0.rawValue }
            switch page {
            case .details:
                details
            case .logs:
                LogConsole(lines: tunnel.logs.map(\.consoleLine), emptyText: "Run the tunnel to see cloudflared output.", onClear: { tunnel.clearLogs() })
            }
        }
    }

    private var details: some View {
        Form {
            Section {
                LabeledContent {
                    Text(tunnel.statusTitle)
                } label: {
                    Label {
                        Text(tunnel.name)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "cloud.fill")
                            .foregroundStyle(tunnel.tint)
                    }
                }
                if let error = tunnel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                TrailingButtons {
                    action
                }
            } footer: {
                if tunnel.runSafety == .managedElsewhere, !tunnel.isRunningHere {
                    Text("Other machines already run this tunnel and this Mac has no local configuration for it. Running it here adds another connector, which splits traffic between origins.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !tunnel.ingressRules.isEmpty {
                Section("Routes") {
                    ForEach(Array(tunnel.ingressRules.enumerated()), id: \.offset) { _, rule in
                        LabeledContent {
                            Text(rule.service)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        } label: {
                            if let url = rule.publicURL, let link = URL(string: url) {
                                Link(rule.hostname ?? url, destination: link)
                                    .contextMenu {
                                        Button("Copy URL") { Pasteboard.copy(url) }
                                    }
                            } else {
                                Text("Fallback")
                            }
                        }
                    }
                }
            }

            Section("Details") {
                LabeledContent {
                    Text(tunnel.id)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } label: {
                    Label("Tunnel ID", systemImage: "number")
                }
                LabeledContent {
                    Text(ingressSource)
                } label: {
                    Label("Routes From", systemImage: "doc.text")
                }
                if let created = tunnel.createdAt {
                    LabeledContent {
                        Text(created.formatted(date: .abbreviated, time: .shortened))
                    } label: {
                        Label("Created", systemImage: "calendar")
                    }
                }
                if let metricsPort = tunnel.metricsPort {
                    LabeledContent {
                        Text(verbatim: "127.0.0.1:\(metricsPort)")
                            .monospacedDigit()
                    } label: {
                        Label("Metrics", systemImage: "chart.bar")
                    }
                }
                if let credentials = tunnel.credentialsPath {
                    LabeledContent {
                        Text((credentials as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } label: {
                        Label("Credentials", systemImage: "key")
                    }
                }
            }

            if !tunnel.edgeConnections.isEmpty {
                Section("Edge Connections") {
                    ForEach(tunnel.edgeConnections) { connection in
                        LabeledContent {
                            if let opened = connection.openedAt {
                                Text(opened, format: .relative(presentation: .named))
                            }
                        } label: {
                            Label {
                                Text(connection.coloName)
                                    .font(.body.monospaced())
                                Text(connection.originIP)
                            } icon: {
                                StatusDot(color: connection.isPendingReconnect ? .orange : .green)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var action: some View {
        switch tunnel.status {
        case .running:
            Button("Stop Tunnel") { model.tunnels.stop(tunnel) }
        case .starting, .stopping:
            ProgressView().controlSize(.small)
        case .stopped, .failed:
            if tunnel.runSafety == .managedElsewhere {
                Button("Run Anyway") { model.tunnels.run(tunnel, allowManagedElsewhere: true) }
                    .disabled(!model.tunnels.isInstalled)
                    .help("Add this Mac as another connector for the tunnel")
            } else {
                Button("Run Tunnel") { model.tunnels.run(tunnel) }
                    .disabled(!model.tunnels.isInstalled)
            }
        }
    }

    private var ingressSource: String {
        switch tunnel.ingressSource {
        case .none: "Unknown"
        case .localConfiguration: "config.yml"
        case .dashboard: "Dashboard"
        }
    }
}
