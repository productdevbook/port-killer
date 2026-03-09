import SwiftUI
import Defaults

struct AutoKillSettingsSection: View {
    @Default(.autoKillRules) private var rules
    @State private var editingRule: AutoKillRule?
    @State private var isAddingRule = false

    var body: some View {
        SettingsGroup("Auto-Kill Rules", icon: "clock.badge.xmark") {
            VStack(spacing: 0) {
                SettingsRowContainer {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically kill processes after a timeout")
                            .fontWeight(.medium)
                        Text("Rules are checked on each port scan cycle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsDivider()

                if rules.isEmpty {
                    SettingsRowContainer {
                        HStack {
                            Text("No rules configured")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Add Rule") {
                                isAddingRule = true
                            }
                            .controlSize(.small)
                        }
                    }
                } else {
                    ForEach(rules) { rule in
                        ruleRow(rule)
                        if rule.id != rules.last?.id {
                            SettingsDivider()
                        }
                    }

                    SettingsDivider()

                    SettingsRowContainer {
                        HStack {
                            Spacer()
                            Button("Add Rule") {
                                isAddingRule = true
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingRule) {
            AutoKillRuleEditor(rule: AutoKillRule(name: "New Rule")) { newRule in
                rules.append(newRule)
            }
        }
        .sheet(item: $editingRule) { rule in
            AutoKillRuleEditor(rule: rule) { updated in
                if let index = rules.firstIndex(where: { $0.id == updated.id }) {
                    rules[index] = updated
                }
            }
        }
    }

    private func ruleRow(_ rule: AutoKillRule) -> some View {
        SettingsRowContainer {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(rule.isEnabled ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(rule.name.isEmpty ? "Unnamed Rule" : rule.name)
                            .fontWeight(.medium)
                    }
                    HStack(spacing: 8) {
                        if !rule.processPattern.isEmpty {
                            Text("Process: \(rule.processPattern)")
                        }
                        if rule.port > 0 {
                            Text("Port: \(rule.port)")
                        }
                        Text("Timeout: \(rule.timeoutMinutes) min")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        editingRule = rule
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)

                    Button {
                        rules.removeAll { $0.id == rule.id }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Rule Editor

struct AutoKillRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: AutoKillRule
    let onSave: (AutoKillRule) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Edit Auto-Kill Rule")
                .font(.headline)
                .padding(.top, 20)

            Form {
                TextField("Rule Name", text: $rule.name)

                Section("Match Criteria") {
                    TextField("Process Pattern (e.g. node*, python*)", text: $rule.processPattern)
                    TextField("Port (0 = any)", value: $rule.port, format: .number)
                }

                Section("Behavior") {
                    Stepper("Timeout: \(rule.timeoutMinutes) minutes", value: $rule.timeoutMinutes, in: 1...1440)
                    Toggle("Notify before killing", isOn: $rule.notifyBeforeKill)
                    Toggle("Enabled", isOn: $rule.isEnabled)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 280)

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.processPattern.isEmpty && rule.port == 0)
            }
            .padding(20)
        }
        .frame(width: 420)
    }
}
