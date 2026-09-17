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
    enum Page: String, CaseIterable, Identifiable {
        case settings = "Settings"
        case logs = "Logs"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    let session: PortForwardSession
    @AppStorage("forwardInspectorPage") private var page: Page = .settings
    @State private var draft = PortForwardConfiguration.placeholder()
    @State private var namespaces: [String] = []
    @State private var services: [KubernetesService] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            InspectorSegmentedPicker(selection: $page, options: Page.allCases) { $0 == .logs && !session.logs.isEmpty ? "Logs (\(session.logs.count))" : $0.rawValue }
            switch page {
            case .settings:
                settings
            case .logs:
                logs
            }
        }
        .onAppear { draft = session.configuration }
        .task { await loadNamespaces() }
        .task(id: draft.namespace) { await loadServices() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            StatusDot(color: session.status.tint, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.configuration.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Group {
                    if case .waitingToReconnect(let date) = session.status {
                        Text("Reconnecting \(date, format: .relative(presentation: .named))")
                    } else if let since = session.connectedSince {
                        Text("Connected \(since, format: .relative(presentation: .named))")
                    } else {
                        Text(session.status.title)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if session.isActive {
                Button("Restart", systemImage: "arrow.clockwise") { session.restart() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Restart")
            }
            Button(session.isActive ? "Stop" : "Start", systemImage: session.isActive ? "stop.fill" : "play.fill") {
                session.toggle()
            }
            .buttonStyle(.glassProminent)
            .tint(session.isActive ? .red : .green)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var settings: some View {
        VStack(spacing: 0) {
            Form {
                if let error = session.lastError, session.status != .connected {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
                Section("Kubernetes") {
                    TextField("Name", text: $draft.name)
                    SuggestionField(title: "Namespace", text: $draft.namespace, suggestions: namespaces)
                    SuggestionField(title: "Service", text: $draft.service, suggestions: services.map(\.name)) { name in
                        if let service = services.first(where: { $0.name == name }), let first = service.ports.first,
                           !service.ports.contains(where: { $0.port == draft.remotePort }) {
                            draft.remotePort = first.port
                        }
                    }
                    TextField("Service Port", value: $draft.remotePort, format: .number.grouping(.never))
                }
                Section("This Mac") {
                    TextField("Local Port", value: $draft.localPort, format: .number.grouping(.never))
                    Toggle("Proxy through socat", isOn: Binding(
                        get: { draft.proxyPort != nil },
                        set: { draft.proxyPort = $0 ? max(1, draft.localPort - 1) : nil }
                    ))
                    if draft.proxyPort != nil {
                        TextField("Proxy Port", value: Binding(get: { draft.proxyPort ?? 0 }, set: { draft.proxyPort = $0 }), format: .number.grouping(.never))
                        Toggle("Allow multiple connections", isOn: $draft.useDirectExec)
                            .help("Starts a separate kubectl port-forward for every client connection")
                    }
                    LabeledContent("Connect to") {
                        Text(verbatim: "localhost:\(draft.effectivePort)")
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                }
                Section("Behavior") {
                    Toggle("Start with Start All", isOn: $draft.isEnabled)
                    Toggle("Reconnect automatically", isOn: $draft.autoReconnect)
                    Toggle("Notify when connected", isOn: $draft.notifyOnConnect)
                    Toggle("Notify when disconnected", isOn: $draft.notifyOnDisconnect)
                }
                Section {
                    Button("Delete Port Forward", role: .destructive) {
                        model.forwards.remove(session.id)
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
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                .background(.bar)
            }
        }
    }

    private var logs: some View {
        LogConsole(
            lines: session.logs.map(\.consoleLine),
            emptyText: "Start the port forward to see kubectl output.",
            exportTitle: session.configuration.name,
            onClear: { session.clearLogs() }
        )
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

struct SuggestionField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]
    var onPick: (String) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, text: $text)
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

struct InspectorSegmentedPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { Text(title($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
