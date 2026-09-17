import PortKillerKit
import SwiftUI

struct ForwardInfoInspector: View {
    @Environment(AppModel.self) private var model
    let session: PortForwardSession

    var body: some View {
        let configuration = session.configuration
        Form {
            Section("Status") {
                InfoRow(title: "Status", value: session.status.title)
                if let since = session.connectedSince {
                    InfoRow(title: "Connected", value: since.formatted(date: .omitted, time: .shortened))
                }
                if case .waitingToReconnect(let date) = session.status {
                    InfoRow(title: "Next Attempt", value: date.formatted(date: .omitted, time: .standard))
                }
                if let error = session.lastError, session.status != .connected {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            Section("Connection") {
                if let context = model.forwards.context {
                    InfoRow(title: "Context", value: context)
                }
                InfoRow(title: "Namespace", value: configuration.namespace)
                InfoRow(title: "Service", value: configuration.service)
                InfoRow(title: "Service Port", value: String(configuration.remotePort))
                InfoRow(title: "Local Address", value: "localhost:\(configuration.effectivePort)")
                if let proxyPort = configuration.proxyPort {
                    InfoRow(title: "kubectl Port", value: String(configuration.localPort))
                    InfoRow(title: "Proxy", value: configuration.useDirectExec ? "socat, one kubectl per connection" : "socat on port \(proxyPort)")
                }
            }
            if model.preferences.locate(.kubectl) == nil {
                Section {
                    ToolNotice(tool: .kubectl, message: "Port forwarding runs kubectl port-forward for you.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ForwardSettingsInspector: View {
    @Environment(AppModel.self) private var model
    let session: PortForwardSession
    @State private var draft = PortForwardConfiguration.placeholder()
    @State private var namespaces: [String] = []
    @State private var services: [KubernetesService] = []

    var body: some View {
        Form {
            Section("Kubernetes") {
                TextField(text: $draft.name) {
                    Label("Name", systemImage: "tag")
                }
                SuggestionField(title: "Namespace", symbol: "folder", text: $draft.namespace, suggestions: namespaces)
                SuggestionField(title: "Service", symbol: "server.rack", text: $draft.service, suggestions: services.map(\.name)) { name in
                    if let service = services.first(where: { $0.name == name }), let first = service.ports.first,
                       !service.ports.contains(where: { $0.port == draft.remotePort }) {
                        draft.remotePort = first.port
                    }
                }
                TextField(value: $draft.remotePort, format: .number.grouping(.never)) {
                    Label("Service Port", systemImage: "number")
                }
            }

            Section("This Mac") {
                TextField(value: $draft.localPort, format: .number.grouping(.never)) {
                    Label("Local Port", systemImage: "laptopcomputer")
                }
                Toggle(isOn: Binding(
                    get: { draft.proxyPort != nil },
                    set: { draft.proxyPort = $0 ? max(1, draft.localPort - 1) : nil }
                )) {
                    Label("Proxy Through socat", systemImage: "arrow.triangle.branch")
                }
                if draft.proxyPort != nil {
                    TextField(value: Binding(get: { draft.proxyPort ?? 0 }, set: { draft.proxyPort = $0 }), format: .number.grouping(.never)) {
                        Label("Proxy Port", systemImage: "arrow.right.circle")
                    }
                    Toggle(isOn: $draft.useDirectExec) {
                        Label("Allow Multiple Connections", systemImage: "person.2")
                    }
                    .help("Starts a separate kubectl port-forward for every client connection")
                }
            }

            Section("Behavior") {
                Toggle(isOn: $draft.isEnabled) {
                    Label("Start with Start All", systemImage: "play")
                }
                Toggle(isOn: $draft.autoReconnect) {
                    Label("Reconnect Automatically", systemImage: "arrow.clockwise")
                }
                Toggle(isOn: $draft.notifyOnConnect) {
                    Label("Notify When Connected", systemImage: "bell")
                }
                Toggle(isOn: $draft.notifyOnDisconnect) {
                    Label("Notify When Disconnected", systemImage: "bell.slash")
                }
            }

            Section {
                TrailingButtons {
                    Button("Delete Port Forward", role: .destructive) {
                        model.forwards.remove(session.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaBar(edge: .bottom) {
            if draft != session.configuration {
                HStack {
                    Button("Revert") { draft = session.configuration }
                    Spacer()
                    Button(session.isActive ? "Apply and Restart" : "Apply") {
                        model.forwards.update(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .onAppear { draft = session.configuration }
        .task { await loadNamespaces() }
        .task(id: draft.namespace) { await loadServices() }
    }

    private func loadNamespaces() async {
        let fetched = (try? await model.forwards.kubectl?.namespaces()) ?? []
        namespaces = model.forwards.namespaces(merging: fetched)
    }

    private func loadServices() async {
        guard !draft.namespace.isEmpty, let kubectl = model.forwards.kubectl else {
            services = []
            return
        }
        guard (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
        let loaded = (try? await kubectl.services(namespace: draft.namespace)) ?? []
        guard !Task.isCancelled else { return }
        services = loaded
    }
}

struct ForwardLogsInspector: View {
    let session: PortForwardSession

    var body: some View {
        LogConsole(
            lines: session.logs.map(\.consoleLine),
            emptyText: "Start the port forward to see kubectl output.",
            exportTitle: session.configuration.name,
            onClear: { session.clearLogs() }
        )
    }
}

private struct SuggestionField: View {
    let title: String
    let symbol: String
    @Binding var text: String
    let suggestions: [String]
    var onPick: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 4) {
            TextField(text: $text) {
                Label(title, systemImage: symbol)
            }
            Menu {
                if suggestions.isEmpty {
                    Text("No Suggestions")
                }
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        text = suggestion
                        onPick(suggestion)
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Choose from the cluster")
        }
    }
}
