import SwiftUI
import Defaults

struct WebhookSettingsSection: View {
    @Default(.webhookURL) private var webhookURL
    @Default(.webhookEvents) private var webhookEvents
    @State private var testResult: TestResult?
    @State private var isTesting = false

    private enum TestResult {
        case success, failure
    }

    var body: some View {
        SettingsGroup("Webhooks", icon: "arrow.up.forward.app") {
            VStack(spacing: 0) {
                // URL field
                SettingsRowContainer {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Webhook URL")
                                .fontWeight(.medium)
                            Text("Send JSON POST requests when port events occur")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            TextField("https://hooks.slack.com/services/...", text: $webhookURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                            if !webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    webhookURL = ""
                                    testResult = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Test button and result
                        if !webhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HStack(spacing: 8) {
                                Button {
                                    testWebhook()
                                } label: {
                                    HStack(spacing: 4) {
                                        if isTesting {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                        Text("Test Webhook")
                                    }
                                }
                                .disabled(isTesting)
                                .controlSize(.small)

                                if let result = testResult {
                                    HStack(spacing: 4) {
                                        Image(systemName: result == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        Text(result == .success ? "Success" : "Failed")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(result == .success ? .green : .red)
                                }
                            }
                        }
                    }
                }

                SettingsDivider()

                // Event toggles
                SettingsRowContainer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Events")
                            .fontWeight(.medium)

                        ForEach(WebhookEvent.allCases, id: \.self) { event in
                            Toggle(isOn: eventBinding(for: event)) {
                                Text(event.displayName)
                                    .font(.callout)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }
    }

    private func eventBinding(for event: WebhookEvent) -> Binding<Bool> {
        Binding(
            get: { webhookEvents.contains(event) },
            set: { enabled in
                if enabled {
                    webhookEvents.insert(event)
                } else {
                    webhookEvents.remove(event)
                }
            }
        )
    }

    private func testWebhook() {
        isTesting = true
        testResult = nil
        Task {
            let success = await WebhookService.shared.sendTest()
            isTesting = false
            testResult = success ? .success : .failure
        }
    }
}
