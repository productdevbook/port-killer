import SwiftUI
import AppKit

/// Picker for a Kubernetes context. An empty selection means "use kubectl's current context".
struct KubeContextPicker: View {
    let processManager: PortForwardProcessManager
    @Binding var context: String
    let kubeconfigPath: String

    @State private var contexts: [String] = []
    @State private var currentContext: String?
    @State private var isLoading = false

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $context) {
                Text(currentContextLabel).tag("")
                if !options.isEmpty {
                    Divider()
                }
                ForEach(options, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .help("Kubernetes context used for discovery and port-forwarding")

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await loadContexts() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload contexts")
            }
        }
        .task(id: kubeconfigPath) {
            // Debounce while the kubeconfig path is being typed.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await loadContexts()
        }
    }

    private var currentContextLabel: String {
        if let currentContext {
            return "Current context (\(currentContext))"
        }
        return "Current context"
    }

    /// Known contexts plus the selected one, so a saved context stays visible even if missing.
    private var options: [String] {
        if !context.isEmpty && !contexts.contains(context) {
            return contexts + [context]
        }
        return contexts
    }

    private func loadContexts() async {
        isLoading = true
        let target = KubectlTarget(kubeconfigPath: kubeconfigPath)
        let fetched = (try? await processManager.fetchContexts(target: target)) ?? []
        let current = await processManager.fetchCurrentContext(target: target)
        contexts = fetched
        currentContext = current
        isLoading = false
    }
}

/// Text field for an optional custom kubeconfig path, with a file browser button.
struct KubeconfigPathField: View {
    @Binding var path: String
    var onCommit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            TextField("Default kubeconfig", text: $path)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onCommit)
                .help("Custom kubeconfig file passed as --kubeconfig. Leave empty for the default.")

            Button {
                browse()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .help("Choose kubeconfig file")

            if !path.isEmpty {
                Button {
                    path = ""
                    onCommit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Use default kubeconfig")
            }
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.title = "Select kubeconfig file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kube")

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            onCommit()
        }
    }
}

/// Compact bar with context and kubeconfig selection, used by the service browsers.
struct KubeTargetBar: View {
    let processManager: PortForwardProcessManager
    @Binding var context: String
    @Binding var kubeconfigPath: String
    let onTargetChanged: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.secondary)
            Text("Context")
                .foregroundStyle(.secondary)
            KubeContextPicker(
                processManager: processManager,
                context: $context,
                kubeconfigPath: kubeconfigPath
            )
            .frame(maxWidth: 280)

            Text("Kubeconfig")
                .foregroundStyle(.secondary)
            KubeconfigPathField(path: $kubeconfigPath, onCommit: onTargetChanged)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: context) { onTargetChanged() }
    }
}
