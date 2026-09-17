import AppKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: setup
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }
                        .buttonStyle(.glass)
                }
                if page < 2 {
                    Button("Skip") { model.completeOnboarding() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    Button("Continue") { withAnimation { page += 1 } }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") { model.completeOnboarding() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 560, height: 470)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to PortKiller")
                .font(.largeTitle.weight(.bold))
            Text("See what listens on every port, stop it in a click, keep Kubernetes forwards connected and share ports through Cloudflare, all from the menu bar.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 12) {
                feature("network", "Every port", .green)
                feature("xmark.octagon", "One-click kill", .red)
                feature("point.3.connected.trianglepath.dotted", "K8s forwards", .indigo)
                feature("cloud", "Tunnels", .orange)
            }
            .padding(.top, 6)
        }
        .padding(28)
    }

    private func feature(_ symbol: String, _ title: String, _ tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .frame(width: 104, height: 76)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var setup: some View {
        @Bindable var preferences = model.preferences
        return VStack(alignment: .leading, spacing: 14) {
            Text("Set Up PortKiller")
                .font(.title.weight(.bold))
                .padding(.horizontal, 20)
            Form {
                Toggle(isOn: Binding(get: { model.loginItem.isEnabled }, set: { model.loginItem.setEnabled($0) })) {
                    Text("Open at login")
                    Text("Keep an eye on ports from the moment you log in.")
                }
                LabeledContent {
                    if model.notifier.isAuthorized {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if model.notifier.isDenied {
                        Button("Open System Settings") { model.notifier.openSystemSettings() }
                    } else {
                        Button("Allow") { Task { await model.notifier.requestAuthorization() } }
                    }
                } label: {
                    Text("Notifications")
                    Text("Hear about watched ports, forwards and tunnels.")
                }
                LabeledContent {
                    ShortcutRecorder(shortcut: $preferences.toggleWindowShortcut)
                } label: {
                    Text("Global shortcut")
                    Text("Show PortKiller from anywhere.")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
        .padding(.top, 24)
        .task { await model.notifier.refreshStatus() }
    }

    private var ready: some View {
        VStack(spacing: 16) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("You're All Set")
                .font(.largeTitle.weight(.bold))
            Text("PortKiller lives in your menu bar. Click its icon for a quick list of ports, or open this window for the full picture.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(28)
    }
}
