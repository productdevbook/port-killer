import PortKillerKit
import SwiftUI

struct PluginView: View {
    @Environment(AppModel.self) private var model
    let plugin: Plugin

    var body: some View {
        @Bindable var model = model
        let store = model.plugins
        let query = model.ports.filter.searchText.trimmingCharacters(in: .whitespaces)
        let allItems = store.items[plugin.id]
        let items = (allItems ?? []).filter { item in
            query.isEmpty || [item.title, item.subtitle ?? "", item.port.map(String.init) ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
        }

        Table(items, selection: $model.pluginSelection) {
            TableColumn("Status") { item in
                HStack(spacing: 6) {
                    StatusDot(color: item.status.tint)
                    Text(item.status.title)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)

            TableColumn("Name") { item in
                Text(item.title)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 200)

            TableColumn("Details") { item in
                Text(item.subtitle ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 240)

            TableColumn("Port") { item in
                Text(item.port.map(String.init) ?? "")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 70)
        }
        .contextMenu(forSelectionType: PluginItem.ID.self) { ids in
            if ids.count == 1, let item = allItems?.first(where: { ids.contains($0.id) }) {
                PluginItemActions(plugin: plugin, item: item)
            }
        } primaryAction: { _ in
            model.inspectorVisible = true
        }
        .overlay {
            if let error = store.itemErrors[plugin.id], allItems == nil {
                ContentUnavailableView {
                    Label("\(plugin.manifest.name) Isn't Responding", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await store.refresh(plugin) } }
                }
            } else if allItems == nil {
                ProgressView()
            } else if items.isEmpty, !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if items.isEmpty {
                ContentUnavailableView("Nothing Here", systemImage: plugin.manifest.icon ?? "puzzlepiece.extension", description: Text("\(plugin.manifest.name) has nothing to show right now."))
            }
        }
        .navigationSubtitle(allItems.map { $0.count == 1 ? "1 item" : "\($0.count) items" } ?? "")
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.refresh(plugin) }
                }
                .disabled(store.loading.contains(plugin.id))
                .help("Ask \(plugin.manifest.name) for its items again")
            }
        }
        .task(id: plugin.id) {
            let interval = max(plugin.manifest.items?.refreshInterval ?? 10, 2)
            while !Task.isCancelled {
                await store.refresh(plugin)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}

struct PluginInspector: View {
    @Environment(AppModel.self) private var model
    let plugin: Plugin

    var body: some View {
        let items = (model.plugins.items[plugin.id] ?? []).filter { model.pluginSelection.contains($0.id) }
        if items.count == 1, let item = items.first {
            PluginItemDetails(plugin: plugin, item: item)
        } else if items.count > 1 {
            ContentUnavailableView("\(items.count) Items Selected", systemImage: plugin.manifest.icon ?? "puzzlepiece.extension")
        } else {
            ContentUnavailableView("Nothing Selected", systemImage: plugin.manifest.icon ?? "puzzlepiece.extension", description: Text(plugin.manifest.summary ?? "Select an item to see its details and actions."))
        }
    }
}

private struct PluginItemDetails: View {
    @Environment(AppModel.self) private var model
    let plugin: Plugin
    let item: PluginItem

    var body: some View {
        let store = model.plugins
        Form {
            Section {
                LabeledContent {
                    Text(item.status.title)
                } label: {
                    Label {
                        Text(item.title)
                            .lineLimit(1)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                        }
                    } icon: {
                        Image(systemName: plugin.manifest.icon ?? "puzzlepiece.extension")
                            .foregroundStyle(item.status.tint)
                    }
                }
                if let url = item.url {
                    LabeledContent {
                        Link(url.absoluteString, destination: url)
                            .lineLimit(1)
                    } label: {
                        Label("URL", systemImage: "link")
                    }
                    .contextMenu { URLActions(url: url) }
                }
                if let port = item.port {
                    LabeledContent {
                        Text(String(port))
                            .monospacedDigit()
                    } label: {
                        Label("Port", systemImage: "number")
                    }
                }
                if let actions = item.actions, !actions.isEmpty {
                    TrailingButtons {
                        ForEach(actions) { action in
                            Button(action.title, role: action.destructive == true ? .destructive : nil) {
                                Task { await store.perform(action, on: item, in: plugin) }
                            }
                            .disabled(store.isPerforming(action, on: item, in: plugin))
                        }
                    }
                }
            }
            if let fields = item.fields, !fields.isEmpty {
                Section("Details") {
                    ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                        LabeledContent(field.label) {
                            Text(field.value)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Section {
                LabeledContent("Provided By") {
                    Text("\(plugin.manifest.name) \(plugin.manifest.version)")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PluginItemActions: View {
    @Environment(AppModel.self) private var model
    let plugin: Plugin
    let item: PluginItem

    var body: some View {
        if let url = item.url {
            URLActions(url: url)
            Divider()
        }
        ForEach(item.actions ?? []) { action in
            Button(action.title, systemImage: action.icon ?? "circle", role: action.destructive == true ? .destructive : nil) {
                Task { await model.plugins.perform(action, on: item, in: plugin) }
            }
        }
    }
}
