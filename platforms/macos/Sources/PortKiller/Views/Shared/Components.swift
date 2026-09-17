import AppKit
import PortKillerKit
import SwiftUI

struct InspectorSegmentedPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { Text(title($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

struct ProcessIcon: View {
    let process: ProcessSnapshot?
    let category: ProcessCategory
    var size: CGFloat = 18

    var body: some View {
        if let image = AppIcons.shared.image(for: process) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: category.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: size * 0.62))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

@Observable
final class AppIcons {
    static let shared = AppIcons()

    private var images: [String: CGImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []

    func image(for process: ProcessSnapshot?) -> CGImage? {
        guard let process, let executable = process.executablePath else { return nil }
        if let image = images[executable] { return image }
        guard requested.insert(executable).inserted else { return nil }
        let bundles = process.appBundleURLs
        Task(name: "Load icon") {
            if let image = await Self.render(bundles) {
                images[executable] = image
            }
        }
        return nil
    }

    @concurrent
    private static func render(_ bundles: [URL]) async -> CGImage? {
        let bundle = bundles.first { url in
            let info = Bundle(url: url)?.infoDictionary
            return info?["CFBundleIconFile"] != nil || info?["CFBundleIconName"] != nil
        }
        guard let bundle, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let pixels = 64
        let icon = NSWorkspace.shared.icon(forFile: bundle.path)
        var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        guard let source = unsafe icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = unsafe CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }
}

struct TrailingButtons<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Spacer()
            content
        }
    }
}

struct NoticeRow<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        LabeledContent {
            actions
        } label: {
            Label {
                Text(title)
                Text(message)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct ToolNotice: View {
    let tool: CommandLineTool
    let message: String

    var body: some View {
        NoticeRow(symbol: "shippingbox", title: "\(tool.name) Isn't Installed", message: message) {
            ToolInstallButton(tool: tool)
        }
        ToolInstallError(tool: tool)
    }
}

struct ToolInstallButton: View {
    @Environment(AppModel.self) private var model
    let tool: CommandLineTool

    var body: some View {
        let installer = model.installer
        if installer.installing.contains(tool.name) {
            ProgressView().controlSize(.small)
        } else if installer.canInstall {
            Button("Install") { installer.install(tool) }
        } else if let url = URL(string: "https://brew.sh") {
            Link("Get Homebrew", destination: url)
        }
    }
}

struct ToolInstallError: View {
    @Environment(AppModel.self) private var model
    let tool: CommandLineTool

    var body: some View {
        if let error = model.installer.errors[tool.name] {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}

struct CommandLineToolRow: View {
    @Environment(AppModel.self) private var model
    let tool: CommandLineTool

    var body: some View {
        let preferences = model.preferences
        let located = preferences.locate(tool)
        LabeledContent {
            if let located {
                Text(located.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                ToolInstallButton(tool: tool)
            }
        } label: {
            Label {
                Text(tool.name)
                if located == nil {
                    Text(tool.isRequired ? "Not installed" : "Not installed (optional)")
                }
            } icon: {
                Image(systemName: located == nil ? "xmark.circle" : "checkmark.circle")
                    .foregroundStyle(located == nil ? .orange : .green)
            }
        }
        TextField(text: Binding(get: { preferences.path(for: tool) }, set: { preferences.setPath($0, for: tool) }), prompt: Text("Detect automatically")) {
            Label("Custom Path", systemImage: "folder")
        }
        .font(.system(.body, design: .monospaced))
        ToolInstallError(tool: tool)
    }
}

struct URLActions: View {
    let url: URL

    var body: some View {
        Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(url) }
        Button("Copy URL", systemImage: "link") { Pasteboard.copy(url.absoluteString) }
    }
}

struct NotificationPermissionControl: View {
    @Environment(AppModel.self) private var model
    var allowTitle = "Allow Notifications"

    var body: some View {
        let notifier = model.notifier
        if notifier.isAuthorized {
            Text("Allowed")
                .foregroundStyle(.secondary)
        } else if notifier.isDenied {
            Button("Open System Settings") { notifier.openSystemSettings() }
        } else {
            Button(allowTitle) {
                Task { await notifier.requestAuthorization() }
            }
            .disabled(!notifier.isAvailable)
        }
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
                if let recorded = KeyShortcut(event: event) {
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

extension Binding {
    func contains<Element: Hashable & Sendable>(_ element: Element) -> Binding<Bool> where Value == Set<Element> {
        Binding<Bool>(
            get: { wrappedValue.contains(element) },
            set: { isIncluded in
                if isIncluded {
                    wrappedValue.insert(element)
                } else {
                    wrappedValue.remove(element)
                }
            }
        )
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
