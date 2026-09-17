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
