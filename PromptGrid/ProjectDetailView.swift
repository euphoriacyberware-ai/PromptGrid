//
//  ProjectDetailView.swift
//  PromptGrid
//
//  Placeholder detail pane for a selected project. Loads the manifest to prove
//  the open path works; the real prompt grid arrives in Phase 4.
//

import SwiftUI
import PromptGridCore

struct ProjectDetailView: View {
    let item: ProjectListItem
    let library: ProjectLibrary

    @State private var project: Project?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let project {
                VStack(spacing: 12) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(project.name).font(.title2).bold()
                    Text("\(project.prompts.count) prompts · \(project.runs.count) runs")
                        .foregroundStyle(.secondary)
                    Text("The prompt grid arrives in Phase 4.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .padding()
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
        .navigationTitle(project?.name ?? item.displayName)
        .task(id: item.id) { load() }
    }

    private func load() {
        project = nil
        loadError = nil
        do {
            project = try library.loadProject(item)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
