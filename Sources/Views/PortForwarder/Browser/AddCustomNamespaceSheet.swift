import SwiftUI

struct AddCustomNamespaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var namespaceInput: String = ""
    @FocusState private var isInputFocused: Bool

    let onAdd: ([String]) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Custom Namespace")
                .font(.headline)

            Text("Enter namespace names (comma-separated for multiple)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("e.g., production, staging, dev", text: $namespaceInput)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .onSubmit {
                    addNamespaces()
                }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addNamespaces()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(namespaceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear {
            isInputFocused = true
        }
    }

    private func addNamespaces() {
        let names = namespaceInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !names.isEmpty else { return }

        onAdd(names)
        dismiss()
    }
}
