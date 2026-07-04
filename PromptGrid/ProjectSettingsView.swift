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
    @Environment(\.dismiss) private var dismiss

    @State private var config = DrawThingsConfigurationDTO()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
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
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            if !loaded { config = store.project.defaultSettings; loaded = true }
        }
    }

    private func commit() {
        store.setDefaultSettings(config)
        store.saveOrReport()
        dismiss()
    }
}
