import PortKillerKit
import SwiftUI

struct PluginRunSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: PluginRunRequest
    @State private var values: [String: String] = [:]
    @State private var runsWhenPortStarts = false
    @State private var showsProblems = false

    private var height: CGFloat {
        let fields = request.inputs.reduce(0) { total, input in total + (input.kind == .multiline ? 100 : 40) + (input.help == nil ? 0 : 20) }
        return min(180 + CGFloat(fields) + (request.confirmation == nil ? 0 : 30) + (isConnection ? 90 : 0), 720)
    }

    private var isConnection: Bool {
        switch request.purpose {
        case .connect, .edit: true
        case .run: false
        }
    }

    private var buttonTitle: String {
        switch request.purpose {
        case .run: request.title.trimmingCharacters(in: ["…"])
        case .connect:
            if case .port(_, .some) = request.target { "Connect and Run" } else { "Connect" }
        case .edit: "Save"
        }
    }

    private var navigationTitle: String {
        switch request.purpose {
        case .run: request.plugin.manifest.name
        case .connect: "New Connection"
        case .edit: "Edit Connection"
        }
    }

    var body: some View {
        let plugins = model.plugins
        let problems = request.inputs.problems(in: values)
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(request.title.trimmingCharacters(in: ["…"]))
                        Text(request.subject)
                    } icon: {
                        Image(systemName: request.icon ?? "puzzlepiece.extension")
                    }
                } footer: {
                    if let confirmation = request.confirmation {
                        Text(confirmation)
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
                    } footer: {
                        if showsProblems, !problems.isEmpty {
                            Text(problems.joined(separator: "\n"))
                                .foregroundStyle(.red)
                        }
                    }
                }
                if isConnection, case .port(let port, _) = request.target {
                    Section {
                        Toggle("Run when port \(String(port)) starts listening", isOn: $runsWhenPortStarts)
                    } footer: {
                        Text("The connection keeps these values. Run it again from its wire in the graph or from the inspector.")
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
                        plugins.submit(request, inputs: values, runsWhenPortStarts: runsWhenPortStarts)
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 480, height: height)
        .onAppear {
            values = plugins.initialInputs(for: request)
            if case .edit(let connection) = request.purpose {
                runsWhenPortStarts = connection.runsWhenPortStarts
            }
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
