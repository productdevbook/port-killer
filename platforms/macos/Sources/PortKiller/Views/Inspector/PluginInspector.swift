import PortKillerKit
import SwiftUI

struct PluginItemInfoInspector: View {
    @Environment(AppModel.self) private var model
    let plugin: Plugin
    let item: PluginItem

    var body: some View {
        Form {
            Section(item.title) {
                InfoRow(title: "Status", value: item.status.title)
                if let subtitle = item.subtitle {
                    InfoRow(title: "Details", value: subtitle)
                }
                if let port = item.port {
                    InfoRow(title: "Port", value: String(port))
                }
                if let targets = item.targetPorts, !targets.isEmpty {
                    InfoRow(title: targets.count == 1 ? "Uses Port" : "Uses Ports", value: targets.map(String.init).joined(separator: ", "))
                }
                if let url = item.url {
                    InfoRow(title: "Address", value: url.absoluteString)
                }
            }
            if let fields = item.fields, !fields.isEmpty {
                Section("Details") {
                    ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                        InfoRow(title: field.label, value: field.value)
                    }
                }
            }
            Section {
                InfoRow(title: "Plugin", value: "\(plugin.manifest.name) \(plugin.manifest.version)")
                if let author = plugin.manifest.author {
                    InfoRow(title: "Author", value: author)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PluginItemActionsInspector: View {
    @Environment(AppModel.self) private var model
    let plugin: Plugin
    let item: PluginItem

    var body: some View {
        let plugins = model.plugins
        let actions = item.actions ?? []
        let runs = plugins.activity.runs(for: .item(item.id), plugin: plugin.id)
        if actions.isEmpty, runs.isEmpty {
            ContentUnavailableView("No Actions", systemImage: InspectorTab.plugins.symbol, description: Text("\(plugin.manifest.name) doesn't offer actions for this item."))
        } else {
            Form {
                if !actions.isEmpty {
                    Section("Actions") {
                        ForEach(actions) { action in
                            PluginActionRow(
                                title: action.title,
                                subtitle: action.destructive == true ? "Can't be undone" : plugin.manifest.name,
                                icon: action.icon ?? plugin.manifest.icon,
                                isRunning: plugins.isRunning(action.id, on: .item(item.id), in: plugin)
                            ) {
                                plugins.run(action, on: item, in: plugin)
                            }
                        }
                    }
                }
                if !runs.isEmpty {
                    Section("Recent") {
                        ForEach(runs.prefix(20)) { run in
                            PluginRunRow(run: run)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
