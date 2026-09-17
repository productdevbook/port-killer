import PortKillerKit
import SwiftUI

struct PluginInputField: View {
    let input: PluginInput
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            field
            if let help = input.help {
                Text(help)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        let prompt = input.placeholder.map { Text($0) }
        switch input.kind {
        case .text, .number:
            TextField(input.label, text: $value, prompt: prompt)
        case .multiline:
            VStack(alignment: .leading, spacing: 6) {
                Text(input.label)
                TextField(input.label, text: $value, prompt: prompt, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(3...10)
                    .font(.body.monospaced())
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.roundedBorder)
            }
        case .secret:
            SecureField(input.label, text: $value, prompt: prompt)
        case .toggle:
            Toggle(input.label, isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" }))
        case .choice:
            Picker(input.label, selection: $value) {
                ForEach(input.options ?? [], id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        }
    }
}
