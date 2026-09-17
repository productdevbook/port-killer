import PortKillerKit
import SwiftUI

struct ServiceBrowser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var namespaces: [String] = []
    @State private var namespace: String?
    @State private var services: [KubernetesService] = []
    @State private var serviceID: KubernetesService.ID?
    @State private var remotePort: Int?
    @State private var localPort = 8080
    @State private var useProxy = false
    @State private var startNow = true
    @State private var loadingNamespaces = false
    @State private var loadingServices = false
    @State private var namespaceError: String?
    @State private var serviceError: String?
    @State private var newNamespace = ""

    var body: some View {
        let service = services.first { $0.id == serviceID }
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                namespaceList
                    .frame(width: 210)
                Divider()
                serviceList
                    .frame(minWidth: 240)
                Divider()
                configuration(service)
                    .frame(width: 280)
            }
            Divider()
            HStack {
                if let context = model.forwards.context {
                    Label(context, systemImage: "circle.hexagongrid")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Port Forward") { add(service) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(service == nil || remotePort == nil)
            }
            .padding(14)
        }
        .frame(width: 860, height: 540)
        .task { await loadNamespaces() }
        .task(id: namespace) { await loadServices() }
        .onChange(of: serviceID) {
            remotePort = services.first { $0.id == serviceID }?.ports.first?.port
        }
        .onChange(of: remotePort) {
            if let remotePort { localPort = PortForwardConfiguration.suggestedLocalPort(forRemotePort: remotePort) }
        }
    }

    private var namespaceList: some View {
        List(selection: $namespace) {
            Section("Namespaces") {
                ForEach(allNamespaces, id: \.self) { name in
                    let isCustom = model.preferences.customNamespaces.contains(name) && !namespaces.contains(name)
                    Label(name, systemImage: isCustom ? "pencil.and.list.clipboard" : "folder")
                        .tag(name)
                        .contextMenu {
                            if model.preferences.customNamespaces.contains(name) {
                                Button("Remove Custom Namespace", role: .destructive) {
                                    model.forwards.removeCustomNamespace(name)
                                }
                            }
                        }
                }
            }
        }
        .overlay {
            if loadingNamespaces, allNamespaces.isEmpty {
                ProgressView()
            } else if let namespaceError, allNamespaces.isEmpty {
                ContentUnavailableView("Cluster Unavailable", systemImage: "exclamationmark.triangle", description: Text(namespaceError))
            }
        }
        .safeAreaBar(edge: .bottom) {
            TextField("Add namespace", text: $newNamespace)
                .textFieldStyle(.bordered)
                .onSubmit {
                    model.forwards.addCustomNamespaces(newNamespace.split(separator: ",").map(String.init))
                    newNamespace = ""
                }
                .padding(8)
        }
    }

    private var serviceList: some View {
        List(selection: $serviceID) {
            Section("Services") {
                ForEach(services) { service in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(service.name)
                            Text("\(service.type) · \(service.ports.count == 1 ? "1 port" : "\(service.ports.count) ports")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "server.rack")
                    }
                    .tag(service.id)
                }
            }
        }
        .overlay {
            if namespace == nil {
                ContentUnavailableView("Choose a Namespace", systemImage: "folder")
            } else if loadingServices {
                ProgressView()
            } else if let serviceError {
                ContentUnavailableView("Couldn't Load Services", systemImage: "exclamationmark.triangle", description: Text(serviceError))
            } else if services.isEmpty {
                ContentUnavailableView("No Services", systemImage: "server.rack")
            }
        }
    }

    @ViewBuilder
    private func configuration(_ service: KubernetesService?) -> some View {
        if let service {
            Form {
                Section("Service Port") {
                    Picker("Port", selection: $remotePort) {
                        ForEach(service.ports) { port in
                            Text(port.title).tag(Optional(port.port))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("This Mac") {
                    TextField("Local Port", value: $localPort, format: .number.grouping(.never))
                    Toggle("Proxy through socat", isOn: $useProxy)
                    LabeledContent("Connect to") {
                        Text(verbatim: "localhost:\(proxyPort ?? localPort)")
                            .monospacedDigit()
                    }
                }
                Section {
                    Toggle("Start right away", isOn: $startNow)
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("Choose a Service", systemImage: "arrow.left")
        }
    }

    private var allNamespaces: [String] {
        model.forwards.namespaces(merging: namespaces)
    }

    private var proxyPort: Int? {
        useProxy ? localPort - 1 : nil
    }

    private func loadNamespaces() async {
        await model.forwards.refreshContext()
        guard let kubectl = model.forwards.kubectl else {
            namespaceError = KubectlError.notInstalled.localizedDescription
            return
        }
        loadingNamespaces = true
        defer { loadingNamespaces = false }
        do {
            namespaces = try await kubectl.namespaces()
            namespaceError = nil
        } catch {
            namespaceError = error.localizedDescription
        }
    }

    private func loadServices() async {
        services = []
        serviceID = nil
        guard let namespace, let kubectl = model.forwards.kubectl else { return }
        loadingServices = true
        let result: Result<[KubernetesService], KubectlError>
        do {
            result = .success(try await kubectl.services(namespace: namespace))
        } catch {
            result = .failure(error)
        }
        guard !Task.isCancelled else { return }
        loadingServices = false
        switch result {
        case .success(let loaded):
            services = loaded
            serviceError = nil
        case .failure(let error):
            serviceError = error.localizedDescription
        }
    }

    private func add(_ service: KubernetesService?) {
        guard let service, let remotePort else { return }
        let configuration = PortForwardConfiguration(
            name: service.name,
            namespace: service.namespace,
            service: service.name,
            localPort: localPort,
            remotePort: remotePort,
            proxyPort: proxyPort
        )
        model.forwards.add(configuration, start: startNow)
        dismiss()
    }
}
