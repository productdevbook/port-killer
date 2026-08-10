/**
 * PortCustomizationRows.swift
 * PortKiller
 *
 * Inline editors for per-port customizations, used by PortDetailView:
 * custom name, description, folder association, and type override.
 */

import SwiftUI
import AppKit

// MARK: - Name Field

/// Editable custom name in the detail header. Placeholder shows the real
/// process name; saving an empty value clears the customization.
struct PortNameField: View {
    let port: PortInfo

    @Environment(AppState.self) private var appState
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(port.processName, text: $draft)
            .textFieldStyle(.plain)
            .font(.title2)
            .fontWeight(.semibold)
            .lineLimit(1)
            .focused($focused)
            .onSubmit { focused = false }
            .onChange(of: focused) { _, isFocused in
                // Persist when focus leaves the field.
                if !isFocused { appState.customizationsState.setName(draft, for: port.port) }
            }
            .onAppear { reseed() }
            .onChange(of: port.port) { _, _ in reseed() }
    }

    private func reseed() {
        draft = appState.customization(for: port.port)?.name ?? ""
    }
}

// MARK: - Description Editor

/// Inline description editor that persists on focus loss
struct PortDescriptionEditor: View {
    let port: PortInfo

    @Environment(AppState.self) private var appState
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description")
                    .font(.headline)
                Spacer()
                if appState.customization(for: port.port)?.description != nil {
                    Button("Clear") {
                        appState.customizationsState.setDescription("", for: port.port)
                        draft = ""
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            TextEditor(text: $draft)
                .focused($focused)
                .font(.body)
                .frame(minHeight: 64, maxHeight: 140)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Describe what runs on port \(String(port.port))…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .onChange(of: focused) { _, isFocused in
                    // Persist when focus leaves the editor.
                    if !isFocused { appState.customizationsState.setDescription(draft, for: port.port) }
                }
        }
        .onAppear { reseed() }
        .onChange(of: port.port) { _, _ in reseed() }
    }

    private func reseed() {
        draft = appState.customization(for: port.port)?.description ?? ""
    }
}

// MARK: - Folder Row

/// Shows the port's effective folder (manual override or detected working
/// directory) with reveal-in-Finder, folder picking, and override clearing
struct PortFolderRow: View {
    let port: PortInfo

    @Environment(AppState.self) private var appState

    private var effectiveFolder: String? { appState.folder(for: port) }
    private var hasOverride: Bool { appState.customization(for: port.port)?.folder != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hasOverride ? "Folder" : "Folder (detected)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let folder = effectiveFolder {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text(folder)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                } else {
                    Text("Not detected")
                        .foregroundStyle(.tertiary)
                }

                Button(hasOverride ? "Change…" : "Set…") {
                    pickFolder()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                if hasOverride {
                    Button("Clear Override") {
                        appState.customizationsState.setFolder(nil, for: port.port)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let current = effectiveFolder {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            appState.customizationsState.setFolder(url.path, for: port.port)
        }
    }
}

// MARK: - Type Picker

/// Per-port process type override picker ("Automatic" clears the override)
struct PortTypePicker: View {
    let port: PortInfo

    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Type")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Type", selection: typeBinding) {
                Text("Automatic").tag(ProcessType?.none)
                Divider()
                ForEach(ProcessType.allCases) { type in
                    Label(type.rawValue, systemImage: type.icon).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var typeBinding: Binding<ProcessType?> {
        Binding(
            get: { appState.customization(for: port.port)?.type },
            set: { appState.setTypeOverride($0, for: port.port) }
        )
    }
}

// MARK: - Detail Row

/// Read-only titled value used in the detail grid
struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
