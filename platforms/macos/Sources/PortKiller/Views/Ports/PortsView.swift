import AppKit
import PortKillerKit
import SwiftUI

struct PortsView: View {
    let item: SidebarItem
    @Environment(AppModel.self) private var model
    @State private var showingRange = false

    var body: some View {
        @Bindable var ports = model.ports
        let rows = model.ports.rows(for: item).sorted(using: model.ports.sortOrder)
        let data = model.preferences.useTreeView ? PortStore.grouped(rows) : rows
        let exposures = model.tunnels.exposuresByPort

        Table(data, children: \.children, selection: $ports.selection, sortOrder: $ports.sortOrder) {
            TableColumn("", value: \.pinRank) { row in
                FavoriteToggle(port: row.port)
            }
            .width(20)

            TableColumn("Port", value: \.port) { row in
                PortCell(row: row, exposed: exposures[row.port] != nil, tunneled: model.tunnels.quickTunnel(for: row.port)?.status == .active)
            }
            .width(min: 64, ideal: 84)

            TableColumn("Process", value: \.processName) { row in
                ProcessCell(row: row, isTerminating: row.listener.map { model.ports.terminating.contains($0.id) } ?? false)
            }
            .width(min: 150, ideal: 230)

            TableColumn("PID", value: \.pid) { row in
                Text(row.listener == nil ? "–" : String(row.pid))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 64)

            TableColumn("Type", value: \.categoryName) { row in
                if row.listener != nil {
                    CategoryBadge(category: row.category)
                }
            }
            .width(min: 80, ideal: 104)

            TableColumn("Address", value: \.address) { row in
                Text(row.address)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(row.address)
            }
            .width(min: 70, ideal: 120)

            TableColumn("User", value: \.user) { row in
                Text(row.user)
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 76)

            TableColumn("Started", value: \.startDate) { row in
                if let date = row.listener?.process.startDate {
                    Text(date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .foregroundStyle(.secondary)
                        .help(date.formatted(date: .abbreviated, time: .standard))
                }
            }
            .width(min: 70, ideal: 96)
        }
        .contextMenu(forSelectionType: PortRow.ID.self) { ids in
            PortContextMenu(ids: ids) { model.ports.requestKill($0) }
        } primaryAction: { ids in
            model.ports.selection = ids
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
        .searchable(text: $ports.filter.searchText, placement: .toolbar, prompt: "Port, process, PID or command")
        .navigationTitle(item.title)
        .navigationSubtitle(subtitle(visible: rows.count))
        .toolbar { toolbar }
        .safeAreaBar(edge: .bottom) {
            PortsStatusBar(visible: rows.count)
        }
        .confirmationDialog(killTitle, isPresented: Binding(get: { !ports.pendingKill.isEmpty }, set: { if !$0 { ports.pendingKill = [] } }), presenting: ports.pendingKill) { targets in
            Button("Kill", role: .destructive) { kill(targets, .graceful) }
            Button("Force Kill") { kill(targets, .force) }
            Button("Kill Process Tree") { kill(targets, .tree) }
            Button("Kill and Close Connections") { kill(targets, .deep) }
        } message: { targets in
            Text(targets.count == 1 ? "PortKiller asks the process to quit, then stops it if it doesn't within a moment." : "PortKiller stops \(targets.count) processes.")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            KillSelectionButton()

            Picker("Layout", selection: Bindable(model.preferences).useTreeView) {
                Label("List", systemImage: "list.bullet").tag(false)
                Label("Group by Process", systemImage: "list.bullet.indent").tag(true)
            }
            .pickerStyle(.segmented)
            .help("Show ports as a list or grouped by process")
        }
        .visibilityPriority(.init(higherThan: .automatic))

        ToolbarItemGroup {
            filterMenu

            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await model.ports.refresh() }
            }
            .help("Scan listening ports now")
        }
    }

    private var filterMenu: some View {
        @Bindable var ports = model.ports
        @Bindable var preferences = model.preferences
        return Menu {
            Toggle("Hide System Processes", isOn: $preferences.hideSystemProcesses)
            Section("Categories") {
                ForEach(ProcessCategory.allCases) { category in
                    Toggle(category.rawValue, isOn: $ports.filter.categories.contains(category))
                }
            }
            Divider()
            Button("Port Range…") { showingRange = true }
            Button("Reset Filters") { ports.filter.reset() }
                .disabled(!ports.filter.isActive)
        } label: {
            Label("Filter", systemImage: ports.filter.isActive || preferences.hideSystemProcesses ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .menuIndicator(.hidden)
        .help("Filter ports")
        .popover(isPresented: $showingRange, arrowEdge: .bottom) {
            PortRangeForm(filter: $ports.filter)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.ports.filter.searchText.isEmpty {
            ContentUnavailableView.search(text: model.ports.filter.searchText)
        } else {
            switch item {
            case .favorites:
                ContentUnavailableView("No Favorites", systemImage: "star", description: Text("Star a port to keep it at hand, even when nothing listens on it."))
            case .watched:
                ContentUnavailableView("No Watched Ports", systemImage: "eye", description: Text("Watch a port to get notified when it starts or stops being used."))
            default:
                ContentUnavailableView("No Listening Ports", systemImage: "network.slash", description: Text("Processes that listen on TCP ports appear here."))
            }
        }
    }

    private func subtitle(visible: Int) -> String {
        visible == 1 ? "1 port" : "\(visible) ports"
    }

    private var killTitle: String {
        let pendingKill = model.ports.pendingKill
        guard pendingKill.count == 1, let port = pendingKill.first else { return "Kill \(pendingKill.count) Processes?" }
        return "Kill \(port.processName) on Port \(port.port)?"
    }

    private func kill(_ targets: [ListeningPort], _ mode: KillMode) {
        model.ports.pendingKill = []
        Task { await model.ports.kill(targets, mode: mode) }
    }
}

private struct KillSelectionButton: View {
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

struct FavoriteToggle: View {
    @Environment(AppModel.self) private var model
    let port: Int

    var body: some View {
        let isFavorite = model.preferences.favorites.contains(port)
        Button {
            model.preferences.toggleFavorite(port)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.borderless)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }
}

struct PortCell: View {
    let row: PortRow
    let exposed: Bool
    let tunneled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(String(row.port))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(row.listener == nil ? .secondary : .primary)
            if row.isWatched {
                Image(systemName: "eye.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .help("Watched")
            }
            if exposed || tunneled {
                Image(systemName: "globe")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help(tunneled ? "Shared with a quick tunnel" : "Exposed by a Cloudflare tunnel")
            }
        }
        .fixedSize()
    }
}

struct ProcessCell: View {
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
                label
            } else {
                ProcessIcon(process: row.listener?.process, category: row.category)
                Text(row.processName)
                    .lineLimit(1)
                    .layoutPriority(1)
                label
                if let children = row.children {
                    Text("\(children.count) ports")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isTerminating {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
        .opacity(isTerminating ? 0.5 : 1)
    }

    @ViewBuilder
    private var label: some View {
        if let label = row.label {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
    }
}

struct PortRangeForm: View {
    @Binding var filter: PortFilter

    var body: some View {
        Form {
            TextField("From", value: $filter.minPort, format: .number.grouping(.never), prompt: Text("1"))
            TextField("To", value: $filter.maxPort, format: .number.grouping(.never), prompt: Text("65535"))
            Button("Clear Range") {
                filter.minPort = nil
                filter.maxPort = nil
            }
            .disabled(!filter.hasRange)
        }
        .formStyle(.grouped)
        .frame(width: 240)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PortsStatusBar: View {
    @Environment(AppModel.self) private var model
    let visible: Int

    var body: some View {
        HStack(spacing: 14) {
            Text(model.ports.ports.count == visible ? "\(visible) listening" : "\(visible) of \(model.ports.ports.count) listening")
            if model.forwards.connectedCount > 0 {
                Label("\(model.forwards.connectedCount) forwarded", systemImage: "point.3.connected.trianglepath.dotted")
            }
            let tunnels = model.tunnels.activeCount
            if tunnels > 0 {
                Label("\(tunnels) tunneled", systemImage: "cloud")
            }
            Spacer()
            if let lastScan = model.ports.lastScan {
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    Text("Updated \(lastScan, format: .relative(presentation: .named))")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
