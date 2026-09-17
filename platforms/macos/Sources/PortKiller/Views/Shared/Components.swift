import AppKit
import PortKillerKit
import SwiftUI

extension ProcessCategory {
    var tint: Color {
        switch self {
        case .webServer: .blue
        case .database: .purple
        case .development: .orange
        case .system: .gray
        case .other: .teal
        }
    }
}

extension SidebarItem {
    var title: String {
        switch self {
        case .allPorts: "All Ports"
        case .favorites: "Favorites"
        case .watched: "Watched"
        case .category(let category): category.rawValue
        case .portForwards: "Port Forwards"
        case .tunnels: "Cloudflare Tunnels"
        case .sponsors: "Sponsors"
        }
    }

    var symbolName: String {
        switch self {
        case .allPorts: "network"
        case .favorites: "star"
        case .watched: "eye"
        case .category(let category): category.symbolName
        case .portForwards: "point.3.connected.trianglepath.dotted"
        case .tunnels: "cloud"
        case .sponsors: "heart"
        }
    }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.45), radius: size / 3)
    }
}

struct CategoryBadge: View {
    let category: ProcessCategory

    var body: some View {
        Text(category.rawValue)
            .font(.caption.weight(.medium))
            .foregroundStyle(category.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(category.tint.opacity(0.14), in: .capsule)
    }
}

struct ProcessIcon: View {
    let process: ProcessSnapshot?
    let category: ProcessCategory
    var size: CGFloat = 18

    var body: some View {
        if let image = AppIcons.icon(for: process) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: category.symbolName)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(category.tint)
                .frame(width: size, height: size)
                .background(category.tint.opacity(0.15), in: .rect(cornerRadius: size * 0.28, style: .continuous))
        }
    }
}

enum AppIcons {
    private static var cache: [String: NSImage?] = [:]

    static func icon(for process: ProcessSnapshot?) -> NSImage? {
        guard let process, let executable = process.executablePath else { return nil }
        if let cached = cache[executable] { return cached }
        let bundle = process.appBundleURLs.first { url in
            let info = Bundle(url: url)?.infoDictionary
            return info?["CFBundleIconFile"] != nil || info?["CFBundleIconName"] != nil
        }
        let image = bundle.map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[executable] = image
        return image
    }
}

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
    @State private var query = ""

    var body: some View {
        let visible = query.isEmpty ? lines : lines.filter { $0.text.localizedCaseInsensitiveContains(query) }
        VStack(spacing: 0) {
            TextField("Filter", text: $query)
                .textFieldStyle(.bordered)
                .controlSize(.small)
                .padding(8)
            Divider()
            if visible.isEmpty {
                ContentUnavailableView(query.isEmpty ? emptyText : "No Matching Lines", systemImage: "text.alignleft")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(visible) { line in
                            row(line)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
            }
        }
        .background(.background.secondary)
    }

    private func row(_ line: ConsoleLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .foregroundStyle(.tertiary)
            if let tag = line.tag {
                Text(tag)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
            }
            Text(line.text)
                .foregroundStyle(color(line.tone))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
    }

    private func color(_ tone: ConsoleLine.Tone) -> Color {
        switch tone {
        case .normal: .primary
        case .accent: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }

    static func markdown(_ lines: [ConsoleLine], title: String) -> String {
        let body = lines.map { line in
            let time = line.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
            return [time, line.tag.map { "[\($0)]" }, line.text].compactMap { $0 }.joined(separator: " ")
        }
        return "# \(title)\n\n```\n\(body.joined(separator: "\n"))\n```\n"
    }
}

struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "Type Shortcut…" : shortcut?.displayString ?? "Record Shortcut")
                    .monospacedDigit()
                    .frame(minWidth: 110)
            }
            .buttonBorderShape(.capsule)
            .tint(isRecording ? .accentColor : nil)
            if shortcut != nil, !isRecording {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    shortcut = nil
                    HotKeyCenter.shared.register(nil)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .onDisappear { if isRecording { stop() } }
    }

    private func start() {
        HotKeyCenter.shared.unregister()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53:
                stop()
            case 51, 117:
                shortcut = nil
                stop()
            default:
                if let recorded = ShortcutRecording.shortcut(from: event) {
                    shortcut = recorded
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotKeyCenter.shared.register(shortcut)
    }
}

struct CommandLineToolRow: View {
    @Environment(AppModel.self) private var model
    let tool: CommandLineTool

    var body: some View {
        let preferences = model.preferences
        let installer = model.installer
        let located = preferences.locate(tool)
        LabeledContent {
            if let located {
                Label(located.path, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if installer.installing.contains(tool.name) {
                ProgressView().controlSize(.small)
            } else if installer.canInstall {
                Button("Install with Homebrew") { installer.install(tool) }
            } else {
                Button("Get Homebrew") {
                    if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
                }
            }
        } label: {
            Text(tool.name)
            if located == nil {
                Text(tool.isRequired ? "Not installed" : "Not installed (optional)")
            }
        }
        TextField("Custom \(tool.name) path", text: Binding(get: { preferences.path(for: tool) }, set: { preferences.setPath($0, for: tool) }), prompt: Text("Detect automatically"))
            .font(.system(.body, design: .monospaced))
        if let error = installer.errors[tool.name] {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        }
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
