import PortKillerKit
import SwiftUI

struct ConsoleLine: Identifiable, Hashable {
    enum Tone {
        case normal
        case accent
        case warning
        case error
    }

    var id: UUID
    var date: Date
    var tag: String?
    var text: String
    var tone: Tone
}

extension ForwardLogEntry {
    var consoleLine: ConsoleLine {
        ConsoleLine(id: id, date: date, tag: source.rawValue, text: message, tone: isError ? .error : source == .portKiller ? .accent : .normal)
    }
}

extension TunnelLogEntry {
    var consoleLine: ConsoleLine {
        let tone: ConsoleLine.Tone = switch level {
        case .error: .error
        case .warning: .warning
        case .request: .accent
        case .info: .normal
        }
        return ConsoleLine(id: id, date: date, tag: nil, text: message, tone: tone)
    }
}

struct LogConsole: View {
    let lines: [ConsoleLine]
    var emptyText = "No output yet."
    var exportTitle: String?
    var onClear: (() -> Void)?
    @State private var query = ""

    private static let timeFormat = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)

    var body: some View {
        let visible = query.isEmpty ? lines : lines.filter { $0.text.localizedCaseInsensitiveContains(query) }
        VStack(spacing: 0) {
            if visible.isEmpty {
                ContentUnavailableView(query.isEmpty ? emptyText : "No Matching Lines", systemImage: "text.alignleft")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(visible) { line in
                            row(line)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
            }
            filterBar
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.background.secondary, in: .capsule)
            if onClear != nil || exportTitle != nil {
                Menu {
                    if let exportTitle {
                        Button("Copy as Markdown", systemImage: "doc.on.doc") {
                            Pasteboard.copy(Self.markdown(lines, title: exportTitle))
                        }
                    }
                    if let onClear {
                        Button("Clear Logs", systemImage: "trash", action: onClear)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.borderless)
                .fixedSize()
                .disabled(lines.isEmpty)
                .help("More")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func row(_ line: ConsoleLine) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                StatusDot(color: color(line.tone), size: 6)
                if let tag = line.tag {
                    Text(tag)
                        .font(.system(size: 11, weight: .semibold))
                }
                Spacer(minLength: 4)
                Text(line.date, format: Self.timeFormat)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(line.tone == .error ? .red : .primary)
                .lineLimit(6)
                .textSelection(.enabled)
        }
    }

    private func color(_ tone: ConsoleLine.Tone) -> Color {
        switch tone {
        case .normal: .secondary
        case .accent: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }

    private static func markdown(_ lines: [ConsoleLine], title: String) -> String {
        let body = lines.map { line in
            [line.date.formatted(timeFormat), line.tag.map { "[\($0)]" }, line.text].compactMap { $0 }.joined(separator: " ")
        }
        return "# \(title)\n\n```\n\(body.joined(separator: "\n"))\n```\n"
    }
}
