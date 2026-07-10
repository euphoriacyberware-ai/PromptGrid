//
//  ProjectGridView.swift
//  PromptGrid
//
//  The prompt × run grid (Specification §6). Rows are prompts, columns are runs.
//  Vertically virtualized via `LazyVStack`; the whole grid scrolls horizontally
//  so iPhone stays the same rows/columns model, just denser (§6). Cells are
//  static by default (§13) — the live editor and cell interactions come later.
//

import SwiftUI
import UniformTypeIdentifiers
import PromptGridCore

struct ProjectGridView: View {
    @Bindable var store: ProjectStore
    @Binding var selectedCell: CellRef?
    let onOpenLightbox: (CellRef) -> Void
    let onRenameProject: (URL, String) -> Void
    @EnvironmentObject private var coordinator: GenerationCoordinator

    @State private var promptPendingDeletion: Prompt?
    @State private var runPendingDeletion: Run?
    @State private var isPresentingSeedPicker = false
    @State private var editingPrompt: EditingPrompt?
    @State private var isPresentingExport = false
    @State private var cellPendingDeletion: CellRef?
    @State private var rowImagesPendingDeletion: Prompt?
    @State private var columnImagesPendingDeletion: Run?
    @State private var isConfirmingGenerateMissing = false
    // Multi-select (§ user request): a set of cells acted on together. On macOS
    // it's driven by ⌘/⇧-click; on iOS by an explicit Select mode toggle.
    @State private var selection: Set<CellRef> = []
    @State private var selectionAnchor: CellRef?
    @State private var isSelectMode = false
    @State private var isConfirmingRegenerate = false
    @State private var isConfirmingDeleteSelection = false
    // Drag-to-reorder: the prompt row currently under a drag.
    @State private var dropTargetPromptID: UUID?
    // Single-image export ("Export Image…" on a completed cell).
    @State private var isExportingImage = false
    @State private var imageDocument: ImageFileDocument?
    @State private var imageExportFilename = "image"
    @State private var isPresentingProjectSettings = false
    @AppStorage(GenerationPreferenceKey.autoGenerateNewRuns) private var autoGenerateNewRuns = false
    @AppStorage(GenerationPreferenceKey.generateMissingOrder) private var generateMissingOrder: GenerationOrder = .bySeed
    @AppStorage(GenerationPreferenceKey.generateMissingSkipRowsWithFinal) private var generateMissingSkipRowsWithFinal = true

    private var missingCount: Int {
        store.missingCellCount(skipRowsWithFinal: generateMissingSkipRowsWithFinal)
    }

    private struct EditingPrompt: Identifiable { let id: UUID }

    private let promptColumnWidth: CGFloat = 260
    private let cellSize: CGFloat = 120
    private let spacing: CGFloat = 8

    private var runs: [Run] { store.project.runs }
    private var prompts: [Prompt] { store.project.prompts }

    var body: some View {
        bodyWithDialogs
            .overlay(alignment: .bottom) { selectionBar }
            .confirmationDialog(
                "Regenerate \(selection.count) Cell\(selection.count == 1 ? "" : "s")?",
                isPresented: $isConfirmingRegenerate
            ) {
                Button("Regenerate \(selection.count)", role: .destructive) { regenerateSelection() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes any existing images in the selected cells and generates them again with re-rolled wildcards. This can’t be undone.")
            }
            .confirmationDialog(
                "Delete \(selectedFilledRefs.count) Selected Image\(selectedFilledRefs.count == 1 ? "" : "s")?",
                isPresented: $isConfirmingDeleteSelection
            ) {
                Button("Delete \(selectedFilledRefs.count)", role: .destructive) { deleteSelection() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes the images in the selected cells, reverting them to empty. This can’t be undone.")
            }
            .fileExporter(
                isPresented: $isExportingImage,
                document: imageDocument,
                contentType: .png,
                defaultFilename: imageExportFilename
            ) { _ in }
    }

    private var bodyWithDialogs: some View {
        gridWithToolbar
            .confirmationDialog(
                "Delete Row Images?",
                isPresented: Binding(
                    get: { rowImagesPendingDeletion != nil },
                    set: { if !$0 { rowImagesPendingDeletion = nil } }
                ),
                presenting: rowImagesPendingDeletion
            ) { prompt in
                let count = store.filledCellCount(inRow: prompt.id)
                Button("Delete \(count) Image\(count == 1 ? "" : "s")", role: .destructive) {
                    deleteRowImages(prompt)
                }
                Button("Cancel", role: .cancel) {}
            } message: { prompt in
                let count = store.filledCellCount(inRow: prompt.id)
                Text("This deletes \(count) image\(count == 1 ? "" : "s") across every run in this row, leaving the prompt in place. This can’t be undone.")
            }
            .confirmationDialog(
                columnImagesPendingDeletion.map { "Delete Run \($0.index) Images?" } ?? "Delete Column Images?",
                isPresented: Binding(
                    get: { columnImagesPendingDeletion != nil },
                    set: { if !$0 { columnImagesPendingDeletion = nil } }
                ),
                presenting: columnImagesPendingDeletion
            ) { run in
                let count = store.filledCellCount(inColumn: run.id)
                Button("Delete \(count) Image\(count == 1 ? "" : "s")", role: .destructive) {
                    deleteColumnImages(run)
                }
                Button("Cancel", role: .cancel) {}
            } message: { run in
                let count = store.filledCellCount(inColumn: run.id)
                Text("This deletes \(count) image\(count == 1 ? "" : "s") across every prompt in this run, leaving the seed column in place. This can’t be undone.")
            }
            .confirmationDialog(
                generateMissingTitle,
                isPresented: $isConfirmingGenerateMissing
            ) {
                Button("Generate \(missingCount)") { generateMissing() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(generateMissingSkipRowsWithFinal
                     ? "Queues a generation for every empty cell in rows that don’t already have a final, re-rolling wildcards and using each prompt’s current settings. This can be a large batch."
                     : "Queues a generation for every empty cell in the grid, re-rolling wildcards and using each prompt’s current settings. This can be a large batch.")
            }
            .sheet(item: $editingPrompt) { editing in
                PromptDetailEditor(store: store, promptID: editing.id)
            }
            .sheet(isPresented: $isPresentingExport) {
                ExportView(store: store)
            }
            .sheet(isPresented: $isPresentingProjectSettings) {
                ProjectSettingsView(store: store,
                                    onRename: { onRenameProject(store.url, $0) })
            }
    }

    private var generateMissingTitle: String {
        "Generate \(missingCount) Missing Image\(missingCount == 1 ? "" : "s")?"
    }

    private var gridWithToolbar: some View {
        VStack(spacing: 0) {
            if let queue = coordinator.queue {
                GenerationStatusBanner(queue: queue)
            }
            if prompts.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: addPrompt) {
                    Label("Add Prompt", systemImage: "plus.rectangle")
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .help("Add a prompt row")
            }
            ToolbarItem {
                Button {
                    isPresentingSeedPicker = true
                } label: {
                    Label("New Run", systemImage: "plus.rectangle.on.rectangle")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Add a run (seed column)")
                .popover(isPresented: $isPresentingSeedPicker, arrowEdge: .bottom) {
                    SeedPickerPopover(isPresented: $isPresentingSeedPicker) { seed, random in
                        createRun(seed: seed, seedWasRandom: random)
                    }
                }
            }
            ToolbarItem {
                Button {
                    isConfirmingGenerateMissing = true
                } label: {
                    Label("Generate Missing", systemImage: "wand.and.stars")
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(missingCount == 0 || !coordinator.isConfigured)
                .help("Generate every empty cell")
            }
            if let queue = coordinator.queue {
                ToolbarItem {
                    QueueToolbarButton(queue: queue)
                }
            }
            ToolbarItem {
                Button {
                    isPresentingExport = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .help("Export images")
            }
            ToolbarItem {
                Button {
                    isPresentingProjectSettings = true
                } label: {
                    Label("Project Settings", systemImage: "slider.horizontal.3")
                }
                .help("Project generation defaults")
            }
#if os(iOS)
            // iOS has no modifier-click, so multi-select needs an explicit mode.
            if !prompts.isEmpty {
                ToolbarItem {
                    Button {
                        isSelectMode.toggle()
                        if !isSelectMode { clearSelection() }
                    } label: {
                        Label(isSelectMode ? "Done" : "Select",
                              systemImage: isSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                }
            }
#endif
        }
        .confirmationDialog(
            "Delete Prompt?",
            isPresented: Binding(
                get: { promptPendingDeletion != nil },
                set: { if !$0 { promptPendingDeletion = nil } }
            ),
            presenting: promptPendingDeletion
        ) { prompt in
            Button("Delete Prompt", role: .destructive) { delete(prompt) }
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            Text(deleteMessage(for: prompt))
        }
        .confirmationDialog(
            runPendingDeletion.map { "Delete Run \($0.index)?" } ?? "Delete Run?",
            isPresented: Binding(
                get: { runPendingDeletion != nil },
                set: { if !$0 { runPendingDeletion = nil } }
            ),
            presenting: runPendingDeletion
        ) { run in
            Button("Delete Run", role: .destructive) { deleteRun(run) }
            Button("Cancel", role: .cancel) {}
        } message: { run in
            Text(deleteMessage(for: run))
        }
        .confirmationDialog(
            "Delete Image?",
            isPresented: Binding(
                get: { cellPendingDeletion != nil },
                set: { if !$0 { cellPendingDeletion = nil } }
            ),
            presenting: cellPendingDeletion
        ) { ref in
            Button("Delete Image", role: .destructive) { deleteCell(ref) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This deletes the generated image. The cell becomes empty and can be generated again. This can’t be undone.")
        }
    }

    // MARK: Grid

    private var grid: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: spacing, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(prompts) { prompt in
                            row(for: prompt)
                        }
                    } header: {
                        headerRow
                    }
                }
                .padding(spacing)
                // Size the content to at least the viewport so it pins top-left
                // (rather than centering) while still growing/scrolling when larger.
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                // A tap on empty space (behind the cells) clears the selection.
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { clearSelection() }
                )
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: spacing) {
            cellFrame(width: promptColumnWidth) {
                Text("Prompt").font(.headline)
            }
            ForEach(runs) { run in
                cellFrame(width: cellSize) {
                    VStack(spacing: 2) {
                        Text("Run \(run.index)").font(.subheadline).bold()
                        Text(run.seedWasRandom ? "random" : "fixed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(run.seed)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .contextMenu {
                    Button("Select Column", systemImage: "checklist") { selectColumn(run.id) }
                    Divider()
                    if store.filledCellCount(inColumn: run.id) > 0 {
                        Button("Delete Column Images…", systemImage: "trash", role: .destructive) {
                            columnImagesPendingDeletion = run
                        }
                    }
                    Button("Delete Run", systemImage: "rectangle.badge.minus", role: .destructive) {
                        runPendingDeletion = run
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func row(for prompt: Prompt) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            promptCell(prompt)
            ForEach(runs) { run in
                let ref = CellRef(promptID: prompt.id, runID: run.id)
                let job = prompt.jobs[run.id]
                let isMultiSelected = selection.contains(ref)
                GridCellView(
                    job: job,
                    thumbnailData: job.flatMap { store.thumbnailData(for: $0) },
                    size: cellSize
                )
                .overlay {
                    if isMultiSelected || selectedCell == ref {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: isMultiSelected ? 3 : 2)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if isMultiSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(4)
                    }
                }
                .contentShape(Rectangle())
                .modifier(CellSelectionGesture(
                    onDoubleTap: { onOpenLightbox(ref) },
                    onPlainTap: { plainTap(ref) },
                    onToggle: { toggleSelection(ref) },
                    onExtend: { extendSelection(to: ref) },
                    isSelectMode: isSelectMode
                ))
                .contextMenu { cellMenu(prompt: prompt, run: run, job: job) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Row \(prompt.order + 1)\(promptTitle(prompt).map { " \($0)" } ?? ""), Run \(run.index), \(cellStatusDescription(job))\(isMultiSelected ? ", selected" : "")")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onOpenLightbox(ref) }
                .accessibilityAction(named: isMultiSelected ? "Deselect" : "Add to selection") { toggleSelection(ref) }
            }
        }
    }

    /// Per-cell context menu. When the right-clicked cell is part of an active
    /// multi-selection, the menu acts on the whole selection (matching the
    /// floating bar); otherwise it's the single-cell menu.
    @ViewBuilder
    private func cellMenu(prompt: Prompt, run: Run, job: GenerationJob?) -> some View {
        let ref = CellRef(promptID: prompt.id, runID: run.id)
        if selection.count > 1 && selection.contains(ref) {
            selectionMenu()
        } else {
            singleCellMenu(prompt: prompt, run: run, job: job, ref: ref)
        }
    }

    /// Actions applied to every cell in the current multi-selection — the
    /// context-menu twin of the floating selection bar.
    @ViewBuilder
    private func selectionMenu() -> some View {
        Section("\(selection.count) Selected") {
            Button("Generate Empty (\(selectedEmptyRefs.count))", systemImage: "wand.and.stars") {
                generateSelection()
            }
            .disabled(selectedEmptyRefs.isEmpty || !coordinator.isConfigured)
            Button("Regenerate \(selection.count)", systemImage: "arrow.clockwise") {
                isConfirmingRegenerate = true
            }
            .disabled(!coordinator.isConfigured)
            if !selectedCompletedJobs.isEmpty {
                Menu {
                    Button("Candidate") { rankSelection(.candidate) }
                    Button("Shortlisted") { rankSelection(.shortlisted) }
                    Button("Final") { rankSelection(.final) }
                } label: {
                    Label("Rank", systemImage: "star")
                }
            }
        }
        if !selectedFilledRefs.isEmpty {
            Button("Delete \(selectedFilledRefs.count) Image\(selectedFilledRefs.count == 1 ? "" : "s")…",
                   systemImage: "trash", role: .destructive) {
                isConfirmingDeleteSelection = true
            }
        }
        Button("Clear Selection", systemImage: "xmark") { clearSelection() }
    }

    @ViewBuilder
    private func singleCellMenu(prompt: Prompt, run: Run, job: GenerationJob?, ref: CellRef) -> some View {
        switch job?.status {
        case .completed:
            if let job {
                Section("Rank") {
                    rankButton(job, .candidate, "Candidate")
                    rankButton(job, .shortlisted, "Shortlisted")
                    rankButton(job, .final, "Final")
                }
                Button("Export Image…", systemImage: "square.and.arrow.up") { exportImage(job) }
                Button("Restore Configuration", systemImage: "arrow.uturn.backward") { restoreConfiguration(job) }
                Button("Restore Prompt", systemImage: "arrow.uturn.backward") { restorePromptFromJob(job) }
            }
        case nil:
            Button("Generate", systemImage: "wand.and.stars") { generateCell(prompt: prompt, run: run) }
                .disabled(!coordinator.isConfigured)
        case .failed:
            if let job {
                Button("Retry", systemImage: "arrow.clockwise") { coordinator.retry(job, in: store) }
                    .disabled(!coordinator.isConfigured)
            }
        default:
            EmptyView()
        }
        Button("Open", systemImage: "arrow.up.backward.and.arrow.down.forward") { onOpenLightbox(ref) }
        if job != nil {
            Divider()
            Button("Delete Image…", systemImage: "trash", role: .destructive) {
                cellPendingDeletion = ref
            }
        }
    }

    // MARK: Multi-select

    /// All cells in visual (row-major) order — the basis for ⇧-click ranges.
    private var orderedCells: [CellRef] {
        prompts.flatMap { p in runs.map { CellRef(promptID: p.id, runID: $0.id) } }
    }

    private func job(for ref: CellRef) -> GenerationJob? {
        prompts.first { $0.id == ref.promptID }?.jobs[ref.runID]
    }

    private var selectedFilledRefs: [CellRef] { selection.filter { job(for: $0) != nil } }
    private var selectedEmptyRefs: [CellRef] { selection.filter { job(for: $0) == nil } }
    private var selectedCompletedJobs: [GenerationJob] {
        selection.compactMap { job(for: $0) }.filter { $0.status == .completed }
    }

    private func inFlightJobIDs(in refs: [CellRef]) -> [UUID] {
        refs.compactMap { job(for: $0) }
            .filter { $0.status == .pending || $0.status == .generating }
            .map(\.id)
    }

    private func plainTap(_ ref: CellRef) {
        selectedCell = ref
        // A single cell is a selection of one, so the action bar appears for it too.
        selection = [ref]
        selectionAnchor = ref
    }

    private func toggleSelection(_ ref: CellRef) {
        if selection.contains(ref) {
            selection.remove(ref)
            // Keep the inspector in sync: point at another selected cell, or close.
            if selectedCell == ref { selectedCell = selection.first }
        } else {
            selection.insert(ref)
            selectedCell = ref
        }
        selectionAnchor = ref
    }

    private func extendSelection(to ref: CellRef) {
        let cells = orderedCells
        guard let anchor = selectionAnchor,
              let a = cells.firstIndex(of: anchor),
              let b = cells.firstIndex(of: ref) else {
            toggleSelection(ref); return
        }
        selection.formUnion(cells[min(a, b)...max(a, b)])
        selectedCell = ref
    }

    private func selectRow(_ promptID: UUID) {
        selection.formUnion(runs.map { CellRef(promptID: promptID, runID: $0.id) })
    }

    private func selectColumn(_ runID: UUID) {
        selection.formUnion(prompts.map { CellRef(promptID: $0.id, runID: runID) })
    }

    private func selectAll() { selection = Set(orderedCells) }
    private func invertSelection() { selection = Set(orderedCells).subtracting(selection) }

    /// Fully deselect — clears the multi-selection and the inspector's cell.
    private func clearSelection() {
        selection.removeAll()
        selectionAnchor = nil
        selectedCell = nil
    }

    private func generateSelection() {
        let created = selectedEmptyRefs.compactMap {
            store.generateCell(promptID: $0.promptID, runID: $0.runID)
        }
        store.saveOrReport()
        coordinator.enqueue(created, for: store)
    }

    private func regenerateSelection() {
        let refs = Array(selection)
        coordinator.cancel(jobIDs: inFlightJobIDs(in: refs))
        for ref in refs { store.deleteCell(promptID: ref.promptID, runID: ref.runID) }
        let created = refs.compactMap {
            store.generateCell(promptID: $0.promptID, runID: $0.runID)
        }
        store.saveOrReport()
        coordinator.enqueue(created, for: store)
    }

    private func deleteSelection() {
        let refs = selectedFilledRefs
        coordinator.cancel(jobIDs: inFlightJobIDs(in: refs))
        for ref in refs { store.deleteCell(promptID: ref.promptID, runID: ref.runID) }
        store.saveOrReport()
        // Keep the selection: the cells still exist (now empty), so the user can
        // immediately act on them again (e.g. Generate) without reselecting.
    }

    private func rankSelection(_ rank: CellRank) {
        for job in selectedCompletedJobs { store.setRank(jobID: job.id, to: rank) }
        store.saveOrReport()
    }

    /// Floating action bar shown while a multi-selection is active.
    @ViewBuilder
    private var selectionBar: some View {
        if !selection.isEmpty {
            let count = selection.count
            HStack(spacing: 12) {
                Text("\(count) selected").font(.callout).bold().fixedSize()
                Divider().frame(height: 16)
                Button { generateSelection() } label: {
                    Label("Generate", systemImage: "wand.and.stars")
                }
                .disabled(selectedEmptyRefs.isEmpty || !coordinator.isConfigured)
                .help("Generate the empty selected cells")
                Button { isConfirmingRegenerate = true } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .disabled(!coordinator.isConfigured)
                .help("Delete and regenerate every selected cell")
                Menu {
                    Button("Candidate") { rankSelection(.candidate) }
                    Button("Shortlisted") { rankSelection(.shortlisted) }
                    Button("Final") { rankSelection(.final) }
                } label: {
                    Label("Rank", systemImage: "star")
                }
                .disabled(selectedCompletedJobs.isEmpty)
                .fixedSize()
                Button(role: .destructive) { isConfirmingDeleteSelection = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedFilledRefs.isEmpty)
                .help("Delete the images in the selected cells")
                Menu {
                    Button("Select All") { selectAll() }
                    Button("Invert Selection") { invertSelection() }
                } label: {
                    Label("Select", systemImage: "checklist")
                }
                .fixedSize()
                Divider().frame(height: 16)
                Button { clearSelection() } label: {
                    Label("Clear", systemImage: "xmark")
                }
                .keyboardShortcut(.cancelAction)
                .help("Clear the selection")
            }
#if os(macOS)
            .labelStyle(.titleAndIcon)
#else
            .labelStyle(.iconOnly)
#endif
            .buttonStyle(.borderless)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.quaternary))
            .shadow(radius: 8, y: 2)
            .padding(.bottom, 16)
        }
    }

    private func rankButton(_ job: GenerationJob, _ rank: CellRank, _ title: String) -> some View {
        Button {
            store.setRank(jobID: job.id, to: rank)
            store.saveOrReport()
        } label: {
            Label(title, systemImage: job.rank == rank ? "checkmark" : rankIcon(rank))
        }
    }

    private func cellStatusDescription(_ job: GenerationJob?) -> String {
        switch job?.status {
        case nil: return "empty"
        case .pending: return "pending"
        case .generating: return "generating"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        case .completed:
            switch job?.rank {
            case .final: return "completed, ranked final"
            case .shortlisted: return "completed, shortlisted"
            default: return "completed"
            }
        }
    }

    private func rankIcon(_ rank: CellRank) -> String {
        switch rank {
        case .candidate: return "circle"
        case .shortlisted: return "star"
        case .final: return "star.fill"
        }
    }

    private func generateCell(prompt: Prompt, run: Run) {
        guard let job = store.generateCell(promptID: prompt.id, runID: run.id) else { return }
        store.saveOrReport()
        coordinator.enqueue([job], for: store)
    }

    private func deleteCell(_ ref: CellRef) {
        store.deleteCell(promptID: ref.promptID, runID: ref.runID)
        store.saveOrReport()
        // The cell stays selected — only its image was deleted, not the cell.
    }

    private func exportImage(_ job: GenerationJob) {
        guard let raw = store.imageData(for: job),
              let bundle = (try? ProjectExporter.singleImage(
                    project: store.project, job: job, imageData: raw, creatorTool: "PromptGrid")) ?? nil
        else { return }
        imageDocument = ImageFileDocument(data: bundle.data)
        imageExportFilename = (bundle.filename as NSString).deletingPathExtension
        isExportingImage = true
    }

    private func restoreConfiguration(_ job: GenerationJob) {
        store.restoreSettings(fromJobID: job.id)
        store.saveOrReport()
    }

    private func restorePromptFromJob(_ job: GenerationJob) {
        store.restorePrompt(fromJobID: job.id)
        store.saveOrReport()
    }

    private func deleteRowImages(_ prompt: Prompt) {
        coordinator.cancel(jobIDs: store.cancellableJobIDs(forPromptID: prompt.id))
        store.deleteRowImages(promptID: prompt.id)
        store.saveOrReport()
        if let selected = selectedCell, selected.promptID == prompt.id { selectedCell = nil }
    }

    private func deleteColumnImages(_ run: Run) {
        coordinator.cancel(jobIDs: store.cancellableJobIDs(forRunID: run.id))
        store.deleteColumnImages(runID: run.id)
        store.saveOrReport()
        if let selected = selectedCell, selected.runID == run.id { selectedCell = nil }
    }

    private func generateMissing() {
        let created = store.generateMissing(order: generateMissingOrder,
                                            skipRowsWithFinal: generateMissingSkipRowsWithFinal)
        store.saveOrReport()
        coordinator.enqueue(created, for: store)
    }

    // MARK: Row reordering

    /// Reorder by dropping one prompt row onto another (drag-and-drop).
    private func movePrompt(withID draggedID: UUID, onto targetID: UUID) -> Bool {
        guard draggedID != targetID,
              let from = prompts.firstIndex(where: { $0.id == draggedID }),
              let to = prompts.firstIndex(where: { $0.id == targetID }) else { return false }
        // `move(fromOffsets:toOffset:)` inserts *before* toOffset in original indexing.
        store.movePrompts(fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to)
        store.saveOrReport()
        dropTargetPromptID = nil
        return true
    }

    /// Insert a new prompt row before/after an existing one, then open it for
    /// editing (matching the flow of tapping an empty new prompt).
    private func insertPrompt(relativeTo prompt: Prompt, after: Bool) {
        let created = store.insertPrompt(relativeTo: prompt.id, after: after)
        store.saveOrReport()
        editingPrompt = EditingPrompt(id: created.id)
    }

    /// Nudge a prompt row up (-1) or down (+1) — the keyboard/menu path.
    private func movePrompt(_ prompt: Prompt, by delta: Int) {
        guard let from = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        let target = from + delta
        guard prompts.indices.contains(target) else { return }
        store.movePrompts(fromOffsets: IndexSet(integer: from), toOffset: delta > 0 ? target + 1 : target)
        store.saveOrReport()
    }

    /// The prompt's title, trimmed, or nil when unset/blank.
    private func promptTitle(_ prompt: Prompt) -> String? {
        guard let title = prompt.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return title
    }

    private func dragPreview(_ prompt: Prompt) -> some View {
        Label(promptTitle(prompt) ?? (prompt.text.isEmpty ? "Row \(prompt.order + 1)" : prompt.text),
              systemImage: "line.3.horizontal")
            .lineLimit(1)
            .padding(8)
            .frame(maxWidth: promptColumnWidth, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func promptCell(_ prompt: Prompt) -> some View {
        Button {
            editingPrompt = EditingPrompt(id: prompt.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Row \(prompt.order + 1)")
                        .foregroundStyle(.tertiary)
                    if let title = promptTitle(prompt) {
                        Text(title)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if prompt.notes?.isEmpty == false {
                        Image(systemName: "note.text").foregroundStyle(.tertiary)
                    }
                    if prompt.referenceImageFilename != nil {
                        Image(systemName: "photo").foregroundStyle(.tertiary)
                    }
                    Image(systemName: "pencil").foregroundStyle(.tertiary)
                }
                .font(.caption2)
                if prompt.text.isEmpty {
                    Text("Empty prompt — tap to edit")
                        .italic()
                        .foregroundStyle(.secondary)
                } else {
                    // Static, truncated by default (§13); tap opens the live editor.
                    Text(prompt.text)
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(width: promptColumnWidth, height: cellSize, alignment: .topLeading)
            .padding(8)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if dropTargetPromptID == prompt.id {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(prompt.id.uuidString) { dragPreview(prompt) }
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first, let draggedID = UUID(uuidString: idString) else { return false }
            return movePrompt(withID: draggedID, onto: prompt.id)
        } isTargeted: { targeted in
            if targeted { dropTargetPromptID = prompt.id }
            else if dropTargetPromptID == prompt.id { dropTargetPromptID = nil }
        }
        .contextMenu {
            Button("Edit Prompt", systemImage: "pencil") {
                editingPrompt = EditingPrompt(id: prompt.id)
            }
            Button("Select Row", systemImage: "checklist") { selectRow(prompt.id) }
            Divider()
            Button("Insert Prompt Above", systemImage: "arrow.up.to.line") {
                insertPrompt(relativeTo: prompt, after: false)
            }
            Button("Insert Prompt Below", systemImage: "arrow.down.to.line") {
                insertPrompt(relativeTo: prompt, after: true)
            }
            Button("Move Up", systemImage: "arrow.up") { movePrompt(prompt, by: -1) }
                .disabled(prompt.order == 0)
            Button("Move Down", systemImage: "arrow.down") { movePrompt(prompt, by: 1) }
                .disabled(prompt.order == prompts.count - 1)
            Divider()
            if store.filledCellCount(inRow: prompt.id) > 0 {
                Button("Delete Row Images…", systemImage: "trash", role: .destructive) {
                    rowImagesPendingDeletion = prompt
                }
            }
            Button("Delete Prompt", systemImage: "rectangle.badge.minus", role: .destructive) {
                promptPendingDeletion = prompt
            }
        }
    }

    private func cellFrame<Content: View>(width: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: width, alignment: .center)
    }

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Prompts", systemImage: "text.badge.plus")
        } description: {
            Text("Add a prompt row to start building your grid.")
        } actions: {
            Button("Add Prompt", action: addPrompt)
        }
    }

    // MARK: Actions

    private func addPrompt() {
        store.addPrompt()
        store.saveOrReport()
    }

    private func delete(_ prompt: Prompt) {
        store.removePrompt(id: prompt.id)
        store.saveOrReport()
    }

    private func createRun(seed: Int, seedWasRandom: Bool) {
        // Off by default: a new run adds an empty column. When on, it queues
        // a generation for every prompt right away.
        let created = store.addRun(seed: seed, seedWasRandom: seedWasRandom,
                                   generateJobs: autoGenerateNewRuns)
        store.saveOrReport()
        if autoGenerateNewRuns {
            coordinator.enqueue(created.jobs, for: store)
        }
    }

    private func deleteRun(_ run: Run) {
        // Cancel in-flight jobs in the queue *before* removing anything (§7 step 1).
        coordinator.cancel(jobIDs: store.cancellableJobIDs(forRunID: run.id))
        store.deleteRun(id: run.id)
        store.saveOrReport()
    }

    private func deleteMessage(for prompt: Prompt) -> String {
        let completed = prompt.jobs.values.filter { $0.status == .completed }.count
        if completed > 0 {
            return "This deletes \(completed) generated image\(completed == 1 ? "" : "s"). This can’t be undone."
        }
        return "This row hasn’t generated any images yet."
    }

    private func deleteMessage(for run: Run) -> String {
        let count = store.completedImageCount(forRunID: run.id)
        return "This deletes \(count) generated image\(count == 1 ? "" : "s"). This can’t be undone."
    }
}

/// Wires a grid cell's tap gestures, branching by platform. macOS uses
/// ⌘-click (toggle) and ⇧-click (range extend) alongside the plain click;
/// iOS toggles on a single tap while an explicit Select mode is active.
private struct CellSelectionGesture: ViewModifier {
    let onDoubleTap: () -> Void
    let onPlainTap: () -> Void
    let onToggle: () -> Void
    let onExtend: () -> Void
    let isSelectMode: Bool

    func body(content: Content) -> some View {
#if os(macOS)
        content
            .highPriorityGesture(TapGesture().modifiers(.command).onEnded(onToggle))
            .highPriorityGesture(TapGesture().modifiers(.shift).onEnded(onExtend))
            .onTapGesture(count: 2, perform: onDoubleTap)
            .onTapGesture(count: 1, perform: onPlainTap)
#else
        content
            .onTapGesture(count: 2, perform: onDoubleTap)
            .onTapGesture(count: 1) {
                if isSelectMode { onToggle() } else { onPlainTap() }
            }
#endif
    }
}
