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

    @EnvironmentObject private var coordinator: GenerationCoordinator
    @State private var store: ProjectStore?
    @State private var loadError: String?
    @State private var selectedCell: CellRef?
    @State private var lightboxCell: CellRef?

    var body: some View {
        Group {
            if let store {
                gridWithInspector(store)
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
        .task(id: item.id) { await open() }
        .onDisappear { coordinator.setActiveStore(nil) }
    }

    @ViewBuilder
    private func gridWithInspector(_ store: ProjectStore) -> some View {
        ProjectGridView(
            store: store,
            selectedCell: $selectedCell,
            onOpenLightbox: { lightboxCell = $0 }
        )
        .inspector(isPresented: Binding(
            get: { selectedCell != nil },
            set: { if !$0 { selectedCell = nil } }
        )) {
            if let selectedCell {
                CellInspector(store: store, cell: selectedCell)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
            } else {
                Text("Select a cell").foregroundStyle(.secondary)
            }
        }
#if os(iOS)
        .fullScreenCover(item: $lightboxCell) { cell in
            LightboxView(store: store, current: cell) { lightboxCell = nil }
        }
#else
        .sheet(item: $lightboxCell) { cell in
            LightboxView(store: store, current: cell) { lightboxCell = nil }
        }
#endif
    }

    private func open() async {
        store = nil
        loadError = nil
        selectedCell = nil
        lightboxCell = nil
        // Download any iCloud placeholders off the main thread first (no-op for a
        // local library) so the package's images read fully.
        let url = item.url
        await Task.detached { FileMaterializer.materializeContents(of: url) }.value
        do {
            let store = try ProjectStore(contentsOf: url)
            self.store = store
            coordinator.setActiveStore(store)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
