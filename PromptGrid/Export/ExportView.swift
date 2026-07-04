//
//  ExportView.swift
//  PromptGrid
//
//  The Export sheet (Specification §11): choose a rank filter (with live counts),
//  pick a destination folder, and write a flat folder of PNGs with embedded XMP
//  metadata. Uses `.fileImporter` in folder mode (NSOpenPanel on macOS,
//  UIDocumentPicker on iOS).
//

import SwiftUI
import UniformTypeIdentifiers
import PromptGridCore

struct ExportView: View {
    let store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    @State private var filter: ExportFilter = .all
    @State private var isChoosingFolder = false
    @State private var isExporting = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    private var selectedCount: Int {
        ProjectExporter.count(in: store.project, filter: filter)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Include") {
                    Picker("Filter", selection: $filter) {
                        ForEach(ExportFilter.allCases) { option in
                            Text("\(option.title) — \(ProjectExporter.count(in: store.project, filter: option))")
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(isExporting)
                }

                Section {
                    Text("Exports a flat folder of PNGs. Each image embeds its prompt and settings as XMP metadata.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isExporting {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Exporting \(selectedCount) image\(selectedCount == 1 ? "" : "s")…")
                        }
                    }
                }
                if let resultMessage {
                    Section {
                        Label(resultMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(isExporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export…") { isChoosingFolder = true }
                        .disabled(selectedCount == 0 || isExporting)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { export(to: folder) }
        }
    }

    private func export(to folder: URL) {
        resultMessage = nil
        errorMessage = nil
        isExporting = true

        // Plan on the main actor (needs the store's image data), then write off-main.
        let units = ProjectExporter.plan(
            project: store.project, filter: filter, creatorTool: "PromptGrid"
        ) { store.imageData(for: $0) }

        Task {
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            do {
                let count = try await Task.detached { try ProjectExporter.write(units, to: folder) }.value
                resultMessage = "Exported \(count) image\(count == 1 ? "" : "s") to “\(folder.lastPathComponent)”."
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }
}
