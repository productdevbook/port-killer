import SwiftUI
import AppKit

struct AddPortPopover: View {
    enum Mode {
        case favorite
        case watch
    }

    let mode: Mode
    let onAdd: (Int, Bool, Bool) -> Void

    @State private var portText = ""
    @State private var notifyOnStart = true
    @State private var notifyOnStop = true
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    private var parsedPort: Int? {
        guard let port = Int(portText), (1...65535).contains(port) else { return nil }
        return port
    }

    private var isValidPort: Bool {
        parsedPort != nil
    }

    private var matchingListener: PortInfo? {
        guard let port = parsedPort else { return nil }
        return appState.ports.first { $0.isActive && $0.port == port }
    }

    private var title: String {
        mode == .favorite ? "Add Favorite Port" : "Add Watched Port"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            TextField("Port (1-65535)", text: $portText)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onSubmit {
                    if isValidPort {
                        handleAdd()
                    }
                }

            if let port = parsedPort {
                HStack(spacing: 6) {
                    if appState.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let listener = matchingListener {
                        Label(
                            "Port \(port) is in use by \(listener.processName) (PID \(listener.pid))",
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(.orange)
                    } else {
                        Label(
                            "No TCP listener on port \(port)",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .lineLimit(2)
            }

            if mode == .watch {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Notify when port starts", isOn: $notifyOnStart)
                        .toggleStyle(.checkbox)

                    Toggle("Notify when port stops", isOn: $notifyOnStop)
                        .toggleStyle(.checkbox)
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Add") {
                    handleAdd()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!isValidPort || (mode == .watch && !notifyOnStart && !notifyOnStop))
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            // Make popover window key so TextField can receive focus
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.keyWindow {
                    window.makeKey()
                }
                isTextFieldFocused = true
            }
        }
    }

    private func handleAdd() {
        guard let port = parsedPort else { return }
        onAdd(port, notifyOnStart, notifyOnStop)
        dismiss()
    }
}
