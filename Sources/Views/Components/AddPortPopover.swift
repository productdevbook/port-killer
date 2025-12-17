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
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool

    private var isValidPort: Bool {
        guard let port = Int(portText) else { return false }
        return port > 0 && port <= 65535
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.keyWindow {
                    window.makeKey()
                }
                isTextFieldFocused = true
            }
        }
    }

    private func handleAdd() {
        guard let port = Int(portText), port > 0, port <= 65535 else { return }
        onAdd(port, notifyOnStart, notifyOnStop)
        dismiss()
    }
}
