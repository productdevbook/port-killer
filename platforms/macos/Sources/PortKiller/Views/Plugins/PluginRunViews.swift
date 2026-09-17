import PortKillerKit
import SwiftUI

struct PluginRunSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: PluginRunRequest
    @State private var values: [String: String] = [:]
    @State private var name = ""
    @State private var runsWhenPortStarts = false
    @State private var connects = true
    @State private var showsProblems = false

    var body: some View {
        let plugins = model.plugins
        let problems = (isNode && name.trimmingCharacters(in: .whitespaces).isEmpty ? ["Name is required."] : []) + request.inputs.problems(in: values)
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(request.title.trimmingCharacters(in: ["…"]))
                        Text(isNode ? request.plugin.manifest.name : request.subject)
                    } icon: {
                        Image(systemName: request.icon ?? "puzzlepiece.extension")
                    }
                    if isNode {
                        TextField("Name", text: $name, prompt: Text("Health Check"))
                    }
                } footer: {
                    if let confirmation = request.confirmation {
                        Text(confirmation)
                    } else if isNode, let summary = request.plugin.manifest.portActions?.first(where: { $0.id == request.actionID })?.summary {
                        Text(summary)
                    }
                }
                if !request.inputs.isEmpty {
                    Section {
                        ForEach(request.inputs) { input in
                            PluginInputField(input: input, value: Binding(
                                get: { values[input.id] ?? input.initialValue },
                                set: { values[input.id] = $0 }
                            ))
                        }
                    }
                }
                if isNode {
                    Section {
                        if case .create(.some(let port)) = request.purpose {
                            Toggle("Connect to port \(String(port))", isOn: $connects)
                        }
                        Toggle("Run when a connected port starts listening", isOn: $runsWhenPortStarts)
                    } footer: {
                        Text("Drag ports onto the node in the graph to connect them. Run it from its ▶ button, its wires or the inspector.")
                    }
                }
                if showsProblems, !problems.isEmpty {
                    Section {
                        Text(problems.joined(separator: "\n"))
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(buttonTitle, role: request.isDestructive ? .destructive : nil) {
                        guard problems.isEmpty else {
                            showsProblems = true
                            return
                        }
                        plugins.submit(request, inputs: values, name: name.trimmingCharacters(in: .whitespaces), runsWhenPortStarts: runsWhenPortStarts, connects: connects)
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 480, height: height)
        .onAppear {
            values = plugins.initialInputs(for: request)
            switch request.purpose {
            case .edit(let node):
                name = node.name
                runsWhenPortStarts = node.runsWhenPortStarts
            case .create:
                name = request.title.trimmingCharacters(in: ["…"])
            case .run:
                break
            }
        }
    }

    private var isNode: Bool {
        switch request.purpose {
        case .create, .edit: true
        case .run: false
        }
    }

    private var height: CGFloat {
        let fields = request.inputs.reduce(0) { total, input in total + (input.kind == .multiline ? 100 : 40) + (input.help == nil ? 0 : 20) }
        return min(180 + CGFloat(fields) + (request.confirmation == nil ? 0 : 30) + (isNode ? 170 : 0), 760)
    }

    private var buttonTitle: String {
        switch request.purpose {
        case .run: request.title.trimmingCharacters(in: ["…"])
        case .create: "Add Node"
        case .edit: "Save"
        }
    }

    private var navigationTitle: String {
        switch request.purpose {
        case .run: request.plugin.manifest.name
        case .create: "New Node"
        case .edit: "Edit Node"
        }
    }
}

struct PluginRunDetails: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let run: PluginRun

    var body: some View {
        let plugins = model.plugins
        let current = plugins.activity.run(run.id) ?? run
        let result = current.result
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status") {
                        PluginRunStatus(run: current, showsTitle: true)
                    }
                    InfoRow(title: "Target", value: targetTitle(current))
                    InfoRow(title: "Started", value: current.started.formatted(date: .omitted, time: .standard))
                    if let duration = current.duration {
                        InfoRow(title: "Duration", value: duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))
                    }
                    if case .failed(let message) = current.state {
                        InfoRow(title: "Error", value: message)
                    } else if let message = result?.message {
                        InfoRow(title: "Message", value: message)
                    }
                }
                if let fields = result?.details?.fields, !fields.isEmpty {
                    Section("Details") {
                        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                            InfoRow(title: field.label, value: field.value)
                        }
                    }
                }
                if let text = result?.details?.text, !text.isEmpty {
                    Section {
                        ScrollView {
                            Text(text)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 120, maxHeight: 320)
                    } header: {
                        Text("Output")
                    } footer: {
                        TrailingButtons {
                            Button("Copy Output") { Pasteboard.copy(text) }
                        }
                    }
                }
                if let log = result?.log {
                    Section("Plugin Log") {
                        Text(log)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(result?.details?.title ?? current.title.trimmingCharacters(in: ["…"]))
            .navigationSubtitle(plugins.plugin(id: current.pluginID)?.manifest.name ?? current.pluginID)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 600, height: 560)
    }

    private func targetTitle(_ run: PluginRun) -> String {
        switch run.target {
        case .port(let port): "Port \(String(port))"
        case .item(let id): model.plugins.items[run.pluginID]?.first { $0.id == id }?.title ?? id
        }
    }
}

struct PluginRunStatus: View {
    let run: PluginRun
    var showsTitle = false

    var body: some View {
        HStack(spacing: 6) {
            switch run.state {
            case .running:
                ProgressView()
                    .controlSize(.small)
                if showsTitle { Text("Running") }
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if showsTitle { Text("Done") }
            case .failed:
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                if showsTitle { Text("Failed") }
            }
        }
    }
}

struct PluginRunRow: View {
    @Environment(AppModel.self) private var model
    let run: PluginRun

    var body: some View {
        Button {
            model.plugins.presentedRun = run
        } label: {
            HStack(spacing: 10) {
                PluginRunStatus(run: run)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(run.title.trimmingCharacters(in: ["…"]))
                    Text(run.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(run.started, format: .dateTime.hour().minute().second())
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(run.isRunning)
    }
}

struct PluginRunBanner: View {
    @Environment(AppModel.self) private var model
    let run: PluginRun

    var body: some View {
        let plugins = model.plugins
        let plugin = plugins.plugin(id: run.pluginID)
        HStack(spacing: 10) {
            Image(systemName: plugin?.manifest.icon ?? "puzzlepiece.extension")
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 1) {
                Text(plugin?.manifest.name ?? run.pluginID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(run.summary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Button("Details") {
                plugins.presentedRun = run
                plugins.dismissBanner()
            }
            Button("Dismiss", systemImage: "xmark") { plugins.dismissBanner() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 520)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 16)
    }
}
