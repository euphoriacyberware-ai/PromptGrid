//
//  ProjectSettingsView.swift
//  PromptGrid
//
//  Per-project settings. For now: the project's default generation configuration,
//  copied into each new prompt. (More project-level settings can join this later.)
//

import SwiftUI
import PromptGridCore

struct ProjectSettingsView: View {
    let store: ProjectStore
    /// Renames the project's `.pgproj` and manifest. Nil in contexts (e.g. previews)
    /// where the library isn't reachable — the name field is then read-only.
    var onRename: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var originalName = ""
    @State private var config = DrawThingsConfigurationDTO()
    @State private var loaded = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Project Name", text: $name)
                        .disabled(onRename == nil)
                }
                Section("Default Generation Settings") {
                    ConfigurationEditor(configuration: $config, minHeight: 280)
                }
                Section {
                    Text("Copied into each new prompt in this project. Existing prompts keep their own settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Project Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commit() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            if !loaded {
                name = store.project.name
                originalName = store.project.name
                config = store.project.defaultSettings
                loaded = true
            }
        }
    }

    private func commit() {
        store.setDefaultSettings(config)
        store.saveOrReport()
        if let onRename, !trimmedName.isEmpty, trimmedName != originalName {
            onRename(trimmedName)
        }
        dismiss()
    }
}
