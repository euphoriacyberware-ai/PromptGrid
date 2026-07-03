//
//  ContentView.swift
//  PromptGrid
//
//  Created by Brian Cantin on 2026-07-03.
//

import SwiftUI
import PromptGridCore

/// The library shell (Specification §2.2, §6): a sidebar listing every project
/// in the library folder, and a detail pane for the selection. The grid itself
/// arrives in Phase 4.
struct ContentView: View {
    @EnvironmentObject private var coordinator: GenerationCoordinator
    @State private var library = ProjectLibrary()
    @State private var selection: ProjectListItem.ID?

    @State private var isPresentingNewProject = false
    @State private var newProjectName = ""
    @State private var projectPendingDeletion: ProjectListItem?
    @State private var isPresentingSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(library.items) { item in
                    ProjectRow(item: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Delete…", role: .destructive) {
                                projectPendingDeletion = item
                            }
                        }
                }
            }
            .navigationTitle("Projects")
            .overlay {
                if library.items.isEmpty {
                    ContentUnavailableView(
                        "No Projects",
                        systemImage: "square.grid.3x3",
                        description: Text("Create a project to get started.")
                    )
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        newProjectName = ""
                        isPresentingNewProject = true
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Button {
                        isPresentingSettings = true
                    } label: {
                        Label("Server Settings", systemImage: "gearshape")
                    }
                }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
#endif
        } detail: {
            if let selection, let item = library.items.first(where: { $0.id == selection }) {
                ProjectDetailView(item: item, library: library)
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "square.grid.3x3",
                    description: Text("Choose a project to see its prompt grid.")
                )
            }
        }
        .task { library.start() }
        .sheet(isPresented: $isPresentingSettings) {
            ServerSettingsView()
        }
        .alert("New Project", isPresented: $isPresentingNewProject) {
            TextField("Name", text: $newProjectName)
            Button("Create") { createProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new project.")
        }
        .alert(
            "Delete Project?",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            presenting: projectPendingDeletion
        ) { item in
            Button("Delete", role: .destructive) { delete(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("“\(item.displayName)” and its generated images will be permanently deleted. This can’t be undone.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { library.lastError != nil },
                set: { if !$0 { library.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
    }

    private func createProject() {
        do {
            let item = try library.createProject(named: newProjectName)
            selection = item.id
        } catch {
            library.lastError = error.localizedDescription
        }
    }

    private func delete(_ item: ProjectListItem) {
        do {
            try library.deleteProject(item)
            if selection == item.id { selection = nil }
        } catch {
            library.lastError = error.localizedDescription
        }
    }
}

/// One sidebar row.
private struct ProjectRow: View {
    let item: ProjectListItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                if let modifiedAt = item.modifiedAt {
                    Text(modifiedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "square.grid.3x3.square")
        }
    }
}

#Preview {
    ContentView()
}
