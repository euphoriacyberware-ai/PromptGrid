//
//  ExportView.swift
//  PromptGrid
//
//  The Export sheet (Specification §11). Two tabs share the same rank Include
//  filter (with live counts): "Images" writes a flat folder of PNGs with embedded
//  XMP metadata, "Prompts" writes the filtered prompt rows as a single .json file.
//  The last-used filter is remembered per project. Uses `.fileImporter` (folder)
//  for images and `.fileExporter` (file) for the JSON.
//

import SwiftUI
import UniformTypeIdentifiers
import PromptGridCore

struct ExportView: View {
    let store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case images = "Images"
        case prompts = "Prompts (JSON)"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .images
    // The Include filter is remembered separately per exporter (e.g. "final images"
    // but "all prompts").
    @State private var imageFilter: ExportFilter = .all
    @State private var promptFilter: ExportFilter = .all
    @State private var isChoosingFolder = false
    @State private var isSavingJSON = false
    @State private var promptsDocument: JSONDocument?
    @State private var isExporting = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var loaded = false

    /// The active mode's filter, as a binding for the Include picker.
    private var filter: Binding<ExportFilter> {
        switch mode {
        case .images: return $imageFilter
        case .prompts: return $promptFilter
        }
    }

    private func count(_ f: ExportFilter) -> Int {
        switch mode {
        case .images: return ProjectExporter.count(in: store.project, filter: f)
        case .prompts: return ProjectExporter.promptCount(in: store.project, filter: f)
        }
    }

    private var selectedCount: Int { count(filter.wrappedValue) }

    private var unitNoun: String {
        switch mode {
        case .images: return "image"
        case .prompts: return "prompt"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Export", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(isExporting)
                }

                Section("Include") {
                    Picker("Filter", selection: filter) {
                        ForEach(ExportFilter.allCases) { option in
                            Text("\(option.title) — \(count(option))").tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(isExporting)
                }

                Section {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isExporting {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Exporting \(selectedCount) \(unitNoun)\(selectedCount == 1 ? "" : "s")…")
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
                    Button("Export…") { beginExport() }
                        .disabled(selectedCount == 0 || isExporting)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 380)
        .onAppear {
            if !loaded {
                imageFilter = store.project.lastImageExportFilter ?? .all
                promptFilter = store.project.lastPromptExportFilter ?? .all
                loaded = true
            }
        }
        .onChange(of: mode) { _, _ in resultMessage = nil; errorMessage = nil }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { exportImages(to: folder) }
        }
        .fileExporter(
            isPresented: $isSavingJSON,
            document: promptsDocument,
            contentType: .json,
            defaultFilename: "\(ProjectExporter.slugify(store.project.name))-prompts"
        ) { result in
            switch result {
            case .success(let url):
                rememberPromptFilter()
                resultMessage = "Exported \(selectedCount) prompt\(selectedCount == 1 ? "" : "s") to “\(url.lastPathComponent)”."
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var footer: String {
        switch mode {
        case .images:
            return "Exports a flat folder of PNGs. Each image embeds its prompt and settings as XMP metadata. Filenames include the project name."
        case .prompts:
            return "Exports the prompt rows (templates, negative prompts, and settings) that have at least one matching image, as a single .json file."
        }
    }

    // MARK: Actions

    private func beginExport() {
        resultMessage = nil
        errorMessage = nil
        switch mode {
        case .images:
            isChoosingFolder = true
        case .prompts:
            do {
                let data = try ProjectExporter.promptsJSON(
                    project: store.project, filter: promptFilter, exportedAt: Date()
                )
                promptsDocument = JSONDocument(data: data)
                isSavingJSON = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func exportImages(to folder: URL) {
        resultMessage = nil
        errorMessage = nil
        isExporting = true

        // Plan on the main actor (needs the store's image data), then write off-main.
        let units = ProjectExporter.plan(
            project: store.project, filter: imageFilter, creatorTool: "PromptGrid"
        ) { store.imageData(for: $0) }

        Task {
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            do {
                let count = try await Task.detached { try ProjectExporter.write(units, to: folder) }.value
                rememberImageFilter()
                resultMessage = "Exported \(count) image\(count == 1 ? "" : "s") to “\(folder.lastPathComponent)”."
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    /// Persist the just-used filter as the project's last-used setting for that
    /// exporter (images and prompts are remembered independently).
    private func rememberImageFilter() {
        guard store.project.lastImageExportFilter != imageFilter else { return }
        store.setLastImageExportFilter(imageFilter)
        store.saveOrReport()
    }

    private func rememberPromptFilter() {
        guard store.project.lastPromptExportFilter != promptFilter else { return }
        store.setLastPromptExportFilter(promptFilter)
        store.saveOrReport()
    }
}

/// A minimal file document wrapping ready-made bytes, for `.fileExporter`.
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// A PNG file document wrapping ready-made image bytes, for `.fileExporter`.
struct ImageFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
