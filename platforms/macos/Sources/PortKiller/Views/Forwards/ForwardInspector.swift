import PortKillerKit
import SwiftUI

struct ForwardInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.forwards.selectedSession {
            ForwardDetails(session: session)
                .id(session.id)
        } else {
            ContentUnavailableView("No Port Forward Selected", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Select a port forward to edit it and read its logs."))
        }
    }
}

private struct ForwardDetails: View {
    enum Page: String, CaseIterable {
        case settings = "Settings"
        case logs = "Logs"
    }

    @Environment(AppModel.self) private var model
    let session: PortForwardSession
    @AppStorage("forwardInspectorPage") private var page: Page = .settings
    @State private var draft = PortForwardConfiguration.placeholder()
    @State private var namespaces: [String] = []
    @State private var services: [KubernetesService] = []

    var body: some View {
        VStack(spacing: 0) {
            InspectorSegmentedPicker(selection: $page, options: Page.allCases) { $0 == .logs && !session.logs.isEmpty ? "Logs (\(session.logs.count))" : $0.rawValue }
            switch page {
            case .settings:
                settings
            case .logs:
                LogConsole(
                    lines: session.logs.map(\.consoleLine),
                    emptyText: "Start the port forward to see kubectl output.",
                    exportTitle: session.configuration.name,
                    onClear: { session.clearLogs() }
                )
            }
        }
        .onAppear { draft = session.configuration }
        .task { await loadNamespaces() }
        .task(id: draft.namespace) { await loadServices() }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent {
                        statusText
                    } label: {
                        Label {
                            Text(session.configuration.name)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .foregroundStyle(session.status.tint)
                        }
                    }
                    if let error = session.lastError, session.status != .connected {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    TrailingButtons {
                        if session.isActive {
                            Button("Restart") { session.restart() }
                        }
                        Button(session.isActive ? "Stop" : "Start") { session.toggle() }
                    }
                }

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
                    LabeledContent {
                        Text(verbatim: "localhost:\(draft.effectivePort)")
                            .monospacedDigit()
                            .textSelection(.enabled)
                    } label: {
                        Label("Connect To", systemImage: "link")
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
    }

    @ViewBuilder
    private var statusText: some View {
        if case .waitingToReconnect(let date) = session.status {
            Text("Reconnecting \(date, format: .relative(presentation: .named))")
        } else if let since = session.connectedSince {
            Text("Connected \(since, format: .relative(presentation: .named))")
        } else {
            Text(session.status.title)
        }
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
