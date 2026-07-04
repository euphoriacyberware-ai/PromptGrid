//
//  PromptDetailEditor.swift
//  PromptGrid
//
//  The prompt detail editor (Specification §12), opened from a prompt row.
//  Split view: left = the non-configuration GenerationRequest fields (prompt
//  text, negative prompt, reference image); right = a plain, debounce-validated
//  JSON editor for DrawThingsConfiguration. Side-by-side on macOS/iPad; a top
//  toggle on iPhone. Edits are committed to the store on Done.
//

import SwiftUI
import UniformTypeIdentifiers
import PromptGridCore

struct PromptDetailEditor: View {
    let store: ProjectStore
    let promptID: UUID

    @Environment(\.dismiss) private var dismiss
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var pane: Pane = .prompt
    private enum Pane: String, CaseIterable { case prompt = "Prompt", configuration = "Configuration" }
#endif

    // Local editing state — committed on Done, discarded on Cancel.
    @State private var text = ""
    @State private var negativePrompt = ""
    @State private var settings = DrawThingsConfigurationDTO()
    @State private var referenceImageData: Data?
    @State private var referenceChanged = false
    @State private var isImporterPresented = false
    @State private var loaded = false

    private var prompt: Prompt? { store.project.prompts.first { $0.id == promptID } }

    var body: some View {
        NavigationStack {
            layout
                .padding()
                .navigationTitle("Edit Prompt")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { commit() }
                    }
                }
        }
        .frame(minWidth: 640, minHeight: 460)
        .onAppear(perform: loadIfNeeded)
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.image]) { result in
            handleImport(result)
        }
    }

    // MARK: Layout

    @ViewBuilder
    private var layout: some View {
#if os(macOS)
        HStack(spacing: 16) { leftPane; Divider(); rightPane }
#else
        if horizontalSizeClass == .regular {
            HStack(spacing: 16) { leftPane; Divider(); rightPane }
        } else {
            VStack {
                Picker("Pane", selection: $pane) {
                    ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch pane {
                case .prompt: leftPane
                case .configuration: rightPane
                }
            }
        }
#endif
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prompt").font(.headline)
            SpellcheckedTextView(text: $text)
                .frame(minHeight: 120)

            Text("Additional Settings").font(.headline).padding(.top, 4)

            Text("Negative Prompt").font(.subheadline)
            SpellcheckedTextView(text: $negativePrompt)
                .frame(minHeight: 70)

            referenceImagePicker
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var referenceImagePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reference Image").font(.subheadline)
            HStack {
                if let data = referenceImageData, let image = platformImage(data) {
                    image.resizable().scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button("Remove") {
                        referenceImageData = nil
                        referenceChanged = true
                    }
                } else {
                    Button("Choose Image…") { isImporterPresented = true }
                    Text("Optional img2img / inpaint source")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configuration (JSON)").font(.headline)
            ConfigurationEditor(configuration: $settings)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Data

    private func loadIfNeeded() {
        guard !loaded, let prompt else { return }
        loaded = true
        text = prompt.text
        negativePrompt = prompt.negativePrompt
        settings = prompt.settings
        referenceImageData = store.referenceImageData(for: prompt)
    }

    private func commit() {
        store.updatePrompt(id: promptID) { prompt in
            prompt.text = text
            prompt.negativePrompt = negativePrompt
            prompt.settings = settings
        }
        if referenceChanged {
            if let data = referenceImageData {
                store.setReferenceImage(promptID: promptID, data: data)
            } else {
                store.clearReferenceImage(promptID: promptID)
            }
        }
        store.saveOrReport()
        dismiss()
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? Data(contentsOf: url) {
            referenceImageData = data
            referenceChanged = true
        }
    }

    // MARK: Helpers

    private func platformImage(_ data: Data) -> Image? {
#if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
#else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
#endif
    }
}
