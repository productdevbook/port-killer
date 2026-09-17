import PortKillerKit
import SwiftUI

struct PortsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var ports = model.ports
        let rows = ports.rows(for: model.portScope).sorted(using: ports.sortOrder)
        let data = model.preferences.useTreeView ? PortStore.grouped(rows) : rows
        let sharedPorts = model.tunnels.sharedPorts

        Table(data, children: \.children, selection: $model.portSelection, sortOrder: $ports.sortOrder) {
            TableColumn("Port", value: \.port) { row in
                PortCell(row: row, isShared: sharedPorts.contains(row.port))
            }
            .width(min: 70, ideal: 90)

            TableColumn("Process", value: \.processName) { row in
                ProcessCell(row: row, isTerminating: row.listener.map { ports.terminating.contains($0.id) } ?? false)
            }
            .width(min: 160, ideal: 260)

            TableColumn("PID", value: \.pid) { row in
                Text(row.listener == nil ? "" : String(row.pid))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Address", value: \.address) { row in
                Text(row.address)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 130)

            TableColumn("User", value: \.user) { row in
                Text(row.user)
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 80)
        }
        .contextMenu(forSelectionType: ItemID.self) { ids in
            PortContextMenu(ids: ids) { model.ports.requestKill($0) }
        } primaryAction: { _ in
            model.inspectorVisible = true
        }
        .onDeleteCommand {
            model.ports.requestKill(model.selectedListeners)
        }
        .overlay {
            if data.isEmpty {
                emptyState
            }
        }
        .navigationSubtitle(subtitle(rows.count))
        .toolbar {
            ToolbarItem {
                KillButton()
            }
            ToolbarItem {
                PortFilterMenu()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let query = model.ports.filter.searchText
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            switch model.portScope {
            case .all:
                ContentUnavailableView("No Listening Ports", systemImage: "network.slash", description: Text("Processes that listen on TCP ports appear here."))
            case .favorites:
                ContentUnavailableView("No Favorites", systemImage: "star", description: Text("Mark a port as a favorite to keep it here, even when nothing listens on it."))
            case .watched:
                ContentUnavailableView("No Watched Ports", systemImage: "eye", description: Text("Watch a port to get notified when it starts or stops being used."))
            }
        }
    }

    private func subtitle(_ count: Int) -> String {
        let ports = count == 1 ? "1 port" : "\(count) ports"
        switch model.portScope {
        case .all: return ports
        case .favorites: return "Favorites · \(ports)"
        case .watched: return "Watched · \(ports)"
        }
    }
}

private struct KillButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selected = model.selectedListeners
        Button("Kill", systemImage: "xmark.octagon") {
            model.ports.requestKill(selected)
        }
        .disabled(selected.isEmpty)
        .help("Kill the selected processes")
    }
}

private struct PortFilterMenu: View {
    @Environment(AppModel.self) private var model
    @State private var showingRange = false

    var body: some View {
        @Bindable var model = model
        @Bindable var ports = model.ports
        @Bindable var preferences = model.preferences
        let isFiltering = model.portScope != .all || ports.filter.isActive || preferences.hideSystemProcesses
        Menu {
            Picker("Show", selection: $model.portScope) {
                Text("All Ports").tag(PortScope.all)
                Text("Favorites").tag(PortScope.favorites)
                Text("Watched").tag(PortScope.watched)
            }
            .pickerStyle(.inline)
            Toggle("Group by Process", isOn: $preferences.useTreeView)
            Toggle("Hide System Processes", isOn: $preferences.hideSystemProcesses)
            Menu("Categories") {
                ForEach(ProcessCategory.allCases) { category in
                    Toggle(category.rawValue, isOn: $ports.filter.categories.contains(category))
                }
            }
            Button("Port Range…") { showingRange = true }
            Divider()
            Button("Reset Filters") {
                ports.filter.reset()
                model.portScope = .all
            }
            .disabled(!ports.filter.isActive && model.portScope == .all)
        } label: {
            Label("Filter", systemImage: isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .menuIndicator(.hidden)
        .help("Filter and group ports")
        .popover(isPresented: $showingRange, arrowEdge: .bottom) {
            PortRangeForm(filter: $ports.filter)
        }
    }
}

private struct PortCell: View {
    let row: PortRow
    let isShared: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(String(row.port))
                .monospacedDigit()
                .fontWeight(.medium)
                .foregroundStyle(row.listener == nil ? .secondary : .primary)
            Group {
                if row.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .help("Favorite")
                }
                if row.isWatched {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(.secondary)
                        .help("Watched")
                }
                if isShared {
                    Image(systemName: "globe")
                        .foregroundStyle(.orange)
                        .help("Shared through a Cloudflare tunnel")
                }
            }
            .font(.caption2)
        }
        .fixedSize()
    }
}

private struct ProcessCell: View {
    let row: PortRow
    let isTerminating: Bool

    var body: some View {
        HStack(spacing: 7) {
            if row.listener == nil {
                Image(systemName: "moon.zzz")
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
                Text("Not Running")
                    .foregroundStyle(.secondary)
            } else {
                ProcessIcon(process: row.listener?.process, category: row.category)
                Text(row.processName)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let children = row.children {
                    Text("\(children.count) ports")
                        .foregroundStyle(.secondary)
                }
            }
            if let label = row.label {
                Text(label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if isTerminating {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .opacity(isTerminating ? 0.5 : 1)
    }
}

private struct PortRangeForm: View {
    @Binding var filter: PortFilter

    var body: some View {
        Form {
            TextField("From", value: $filter.minPort, format: .number.grouping(.never), prompt: Text("1"))
            TextField("To", value: $filter.maxPort, format: .number.grouping(.never), prompt: Text("65535"))
            TrailingButtons {
                Button("Clear Range") {
                    filter.minPort = nil
                    filter.maxPort = nil
                }
                .disabled(!filter.hasRange)
            }
        }
        .formStyle(.grouped)
        .frame(width: 240)
        .fixedSize(horizontal: false, vertical: true)
    }
}
