import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    @State private var showAddFavoritePopover = false
    @State private var showAddWatchPopover = false

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedSidebarItem) {
            Section("Categories") {
                sidebarRow(.allPorts, count: appState.ports.count)

                // Favorites row with add button
                favoritesRow

                // Watched row with add button
                watchedRow
            }

            Section("Process Types") {
                ForEach(ProcessType.allCases) { type in
                    sidebarRow(.processType(type), count: countForType(type))
                }
            }

            Section("Filters") {
                filterControls
            }

            Section {
                Label {
                    Text("Sponsors")
                } icon: {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                }
                .tag(SidebarItem.sponsors)

                Label("Settings", systemImage: "gear")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    // MARK: - Favorites Row

    private var favoritesRow: some View {
        Label {
            HStack {
                Text("Favorites")
                Spacer()

                Button {
                    showAddFavoritePopover = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add Favorite Port")
                .popover(isPresented: $showAddFavoritePopover) {
                    AddPortPopover(mode: .favorite) { port, _, _ in
                        appState.favorites.insert(port)
                    }
                }

                Text("\(favoritesCount)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(minWidth: 20)
            }
        } icon: {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
        }
        .tag(SidebarItem.favorites)
        .contextMenu {
            Button {
                showAddFavoritePopover = true
            } label: {
                Label("Add Port...", systemImage: "plus")
            }
        }
    }

    // MARK: - Watched Row

    private var watchedRow: some View {
        Label {
            HStack {
                Text("Watched")
                Spacer()

                Button {
                    showAddWatchPopover = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add Watched Port")
                .popover(isPresented: $showAddWatchPopover) {
                    AddPortPopover(mode: .watch) { port, onStart, onStop in
                        appState.watchedPorts.append(
                            WatchedPort(port: port, notifyOnStart: onStart, notifyOnStop: onStop)
                        )
                    }
                }

                Text("\(watchedCount)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(minWidth: 20)
            }
        } icon: {
            Image(systemName: "eye.fill")
                .foregroundStyle(.blue)
        }
        .tag(SidebarItem.watched)
        .contextMenu {
            Button {
                showAddWatchPopover = true
            } label: {
                Label("Add Port...", systemImage: "plus")
            }
        }
    }

    // MARK: - Standard Row

    private func sidebarRow(_ item: SidebarItem, count: Int) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } icon: {
            Image(systemName: item.icon)
        }
        .tag(item)
    }

    // MARK: - Filter Controls

    @ViewBuilder
    private var filterControls: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Port Range")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("Min", value: $state.filter.minPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("-")
                        .foregroundStyle(.secondary)
                    TextField("Max", value: $state.filter.maxPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }

            if appState.filter.isActive {
                Button("Reset Filters") {
                    appState.filter.reset()
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var favoritesCount: Int {
        appState.favorites.count
    }

    private var watchedCount: Int {
        appState.watchedPorts.count
    }

    private func countForType(_ type: ProcessType) -> Int {
        appState.ports.filter { $0.processType == type }.count
    }
}
