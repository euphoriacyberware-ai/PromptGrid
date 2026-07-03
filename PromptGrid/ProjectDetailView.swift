//
//  ProjectDetailView.swift
//  PromptGrid
//
//  Loads the selected project into an editable `ProjectStore` and hosts its grid
//  (Specification §6). Opening happens per-selection; the store owns save-back.
//

import SwiftUI
import PromptGridCore

struct ProjectDetailView: View {
    let item: ProjectListItem
    let library: ProjectLibrary

    @State private var store: ProjectStore?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let store {
                ProjectGridView(store: store)
                    .navigationTitle(store.project.name)
                    .alert(
                        "Couldn’t Save",
                        isPresented: Binding(
                            get: { store.lastError != nil },
                            set: { if !$0 { store.lastError = nil } }
                        )
                    ) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(store.lastError ?? "")
                    }
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn’t Open Project",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .task(id: item.id) { open() }
    }

    private func open() {
        store = nil
        loadError = nil
        do {
            store = try ProjectStore(contentsOf: item.url)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
