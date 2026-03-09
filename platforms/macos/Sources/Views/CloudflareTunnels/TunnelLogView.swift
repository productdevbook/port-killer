import SwiftUI

struct TunnelLogView: View {
    let tunnel: CloudflareTunnelState
    @State private var searchText = ""
    @State private var filterLevel: TunnelLogEntry.LogLevel?

    private var filteredLogs: [TunnelLogEntry] {
        var logs = tunnel.logs
        if let level = filterLevel {
            logs = logs.filter { $0.level == level }
        }
        if !searchText.isEmpty {
            logs = logs.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
        }
        return logs
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)

                Spacer()

                // Level filter
                Picker("", selection: $filterLevel) {
                    Text("All").tag(nil as TunnelLogEntry.LogLevel?)
                    Text("Requests").tag(TunnelLogEntry.LogLevel.request as TunnelLogEntry.LogLevel?)
                    Text("Errors").tag(TunnelLogEntry.LogLevel.error as TunnelLogEntry.LogLevel?)
                    Text("Warnings").tag(TunnelLogEntry.LogLevel.warning as TunnelLogEntry.LogLevel?)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Text("\(filteredLogs.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)

                Button {
                    tunnel.clearLogs()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear logs")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Log entries
            if filteredLogs.isEmpty {
                ContentUnavailableView {
                    Label("No Logs", systemImage: "doc.text")
                } description: {
                    Text(tunnel.logs.isEmpty ? "Logs will appear here as requests come in" : "No logs match the current filter")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredLogs) { entry in
                                logEntryRow(entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .onChange(of: tunnel.logs.count) { _, _ in
                        if let last = filteredLogs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func logEntryRow(_ entry: TunnelLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)

            // Level indicator
            Circle()
                .fill(levelColor(entry.level))
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            // Message
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(entry.level == .error ? .red : .primary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private func levelColor(_ level: TunnelLogEntry.LogLevel) -> Color {
        switch level {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        case .request: .blue
        }
    }
}
