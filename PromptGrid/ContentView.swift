//
//  ContentView.swift
//  PromptGrid
//
//  Created by Brian Cantin on 2026-07-03.
//

import SwiftUI
import UniformTypeIdentifiers
import PromptGridCore

/// The library shell (Specification §2.2, §6): a sidebar listing every project
/// in the library folder, and a detail pane for the selection. The grid itself
/// arrives in Phase 4.
struct ContentView: View {
    @EnvironmentObject private var coordinator: GenerationCoordinator
    @State private var library = ProjectLibrary(libraryURL: LibraryLocationStore.resolveLibraryURL())
    @State private var selection: ProjectListItem.ID?

    @State private var isPresentingNewProject = false
    @State private var newProjectName = ""
    @State private var projectPendingDeletion: ProjectListItem?
    @State private var isPresentingSettings = false
    @State private var projectSettings: ProjectSettingsPresentation?
    @State private var isImportingProject = false
    @State private var pendingImport: PendingImport?
    @State private var importNameField = ""

    private struct ProjectSettingsPresentation: Identifiable {
        let id: URL
        let store: ProjectStore
    }

    /// A decoded prompts import awaiting a name-collision decision.
    private struct PendingImport: Identifiable {
        let id = UUID()
        let originalName: String
        let prompts: [Prompt]
        let defaultSettings: DrawThingsConfigurationDTO
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(library.items) { item in
                    ProjectRow(item: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Project Settings…", systemImage: "slider.horizontal.3") {
                                openProjectSettings(item)
                            }
                            Button("Delete…", systemImage: "trash", role: .destructive) {
                                projectPendingDeletion = item
                            }
                        }
                }
            }
            .navigationTitle("Projects")
            .overlay {
                if library.items.isEmpty {
                    ContentUnavailableView {
                        Label("No Projects", systemImage: "square.grid.3x3")
                    } description: {
                        Text("Create your first project to start building a grid of prompts and seeds.")
                    } actions: {
                        Button("New Project") {
                            newProjectName = ""
                            isPresentingNewProject = true
                        }
                    }
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
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New project")
                }
                ToolbarItem {
                    Button {
                        isImportingProject = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .help("Import a prompts .json file as a new project")
                }
                ToolbarItem {
                    Button {
                        isPresentingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Settings")
                }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
#endif
        } detail: {
            if let selection, let item = library.items.first(where: { $0.id == selection }) {
                ProjectDetailView(item: item, library: library, onRenameProject: renameProject)
            } else {
                ContentUnavailableView(
                    "Select a Project",
                    systemImage: "square.grid.3x3",
                    description: Text("Choose a project to see its prompt grid.")
                )
            }
        }
        .task { library.start() }
        .onChange(of: library.libraryURL) { _, _ in selection = nil }
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView(library: library)
        }
        .sheet(item: $projectSettings) { presentation in
            ProjectSettingsView(store: presentation.store,
                                onRename: { renameProject(at: presentation.store.url, to: $0) })
        }
        .alert("New Project", isPresented: $isPresentingNewProject) {
            TextField("Name", text: $newProjectName)
            Button("Create") { createProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new project.")
        }
        .fileImporter(isPresented: $isImportingProject, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result { importFile(at: url) }
        }
        .alert(
            "Project Already Exists",
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            ),
            presenting: pendingImport
        ) { pending in
            TextField("Name", text: $importNameField)
            Button("Import") {
                performImport(name: importNameField, from: pending, replace: false)
            }
            Button("Replace", role: .destructive) {
                performImport(name: pending.originalName, from: pending, replace: true)
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: { pending in
            Text("A project named “\(pending.originalName)” already exists. Import under a different name, or replace the existing project (this permanently deletes it and its images).")
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

    private func openProjectSettings(_ item: ProjectListItem) {
        // Reuse the live store if this project is already open, so the change is
        // reflected in the detail pane. Otherwise load it from disk.
        if let openStore = coordinator.openStore(for: item.url) {
            projectSettings = ProjectSettingsPresentation(id: item.url, store: openStore)
            return
        }
        do {
            let store = try ProjectStore(contentsOf: item.url)
            projectSettings = ProjectSettingsPresentation(id: item.url, store: store)
        } catch {
            library.lastError = error.localizedDescription
        }
    }

    private func renameProject(at url: URL, to newName: String) {
        // The rename moves the .pgproj, so its URL — the selection identity —
        // changes. Note whether it was selected *before* the move.
        let wasSelected = selection == url
        do {
            let renamed = try library.renameProject(at: url, to: newName)
            // Reselect the moved project using the entry as it appears in the
            // refreshed list, so the id is one the sidebar List actually contains
            // (else NavigationSplitView clears the selection to nil).
            if wasSelected {
                let item = library.items.first { $0.url == renamed.url } ?? renamed
                selection = item.id
            }
        } catch {
            library.lastError = error.localizedDescription
        }
    }

    private func importFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let imported = try ProjectImporter.decode(from: data)
            if library.projectExists(named: imported.name) {
                // Prompt to rename or replace; pre-fill the field with the name.
                importNameField = imported.name
                pendingImport = PendingImport(originalName: imported.name,
                                              prompts: imported.prompts,
                                              defaultSettings: imported.defaultSettings)
            } else {
                createImported(name: imported.name, prompts: imported.prompts,
                               defaultSettings: imported.defaultSettings, replace: false)
            }
        } catch {
            library.lastError = error.localizedDescription
        }
    }

    private func performImport(name: String, from pending: PendingImport, replace: Bool) {
        createImported(name: name, prompts: pending.prompts,
                       defaultSettings: pending.defaultSettings, replace: replace)
        pendingImport = nil
    }

    private func createImported(name: String, prompts: [Prompt],
                                defaultSettings: DrawThingsConfigurationDTO, replace: Bool) {
        do {
            let item = try library.importProject(named: name, prompts: prompts,
                                                 defaultSettings: defaultSettings,
                                                 replaceExisting: replace)
            selection = item.id
        } catch {
            library.lastError = error.localizedDescription
        }
    }

    private func createProject() {
        do {
            let item = try library.createProject(named: newProjectName,
                                                 defaultSettings: AppDefaults.generationConfig())
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
