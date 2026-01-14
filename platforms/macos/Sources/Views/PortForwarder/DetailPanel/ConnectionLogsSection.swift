import SwiftUI

struct ConnectionLogsSection: View {
    let connection: PortForwardConnectionState

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Logs header
            HStack {
                Text("Logs")
                    .font(.headline)

                if !connection.logs.isEmpty {
                    Text("(\(connection.logs.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !connection.logs.isEmpty {
                    Button {
                        ClipboardService.copyLogsAsMarkdown(connection.logs, connectionName: connection.config.name)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy All Logs (Markdown)")

                    Button {
                        connection.clearLogs()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear Logs")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if connection.logs.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No logs yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(connection.logs) { log in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(Self.dateFormatter.string(from: log.timestamp))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.tertiary)

                                    Text(log.type == .portForward ? "kubectl" : "socat")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(log.type == .portForward ? .blue : .purple)
                                        .frame(width: 50, alignment: .leading)

                                    Text(log.message)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(log.isError ? .red : .primary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(log.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .onChange(of: connection.logs.count) {
                        if let lastLog = connection.logs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}
