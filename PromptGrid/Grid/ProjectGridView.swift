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
import PromptGridCore

struct ProjectGridView: View {
    @Bindable var store: ProjectStore
    @Binding var selectedCell: CellRef?
    let onOpenLightbox: (CellRef) -> Void
    @EnvironmentObject private var coordinator: GenerationCoordinator

    @State private var promptPendingDeletion: Prompt?
    @State private var runPendingDeletion: Run?
    @State private var isPresentingSeedPicker = false
    @State private var editingPrompt: EditingPrompt?

    private struct EditingPrompt: Identifiable { let id: UUID }

    private let promptColumnWidth: CGFloat = 260
    private let cellSize: CGFloat = 120
    private let spacing: CGFloat = 8

    private var runs: [Run] { store.project.runs }
    private var prompts: [Prompt] { store.project.prompts }

    var body: some View {
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
            }
            ToolbarItem {
                Button {
                    isPresentingSeedPicker = true
                } label: {
                    Label("New Run", systemImage: "plus.rectangle.on.rectangle")
                }
                .popover(isPresented: $isPresentingSeedPicker, arrowEdge: .bottom) {
                    SeedPickerPopover(isPresented: $isPresentingSeedPicker) { seed, random in
                        createRun(seed: seed, seedWasRandom: random)
                    }
                }
            }
            if let queue = coordinator.queue {
                ToolbarItem {
                    QueueToolbarButton(queue: queue)
                }
            }
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
        .sheet(item: $editingPrompt) { editing in
            PromptDetailEditor(store: store, promptID: editing.id)
        }
    }

    // MARK: Grid

    private var grid: some View {
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
                    Button("Delete Run", role: .destructive) {
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
                GridCellView(
                    job: job,
                    thumbnailData: job.flatMap { store.thumbnailData(for: $0) },
                    size: cellSize
                )
                .overlay {
                    if selectedCell == ref {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onOpenLightbox(ref) }
                .onTapGesture(count: 1) { selectedCell = ref }
            }
        }
        .contextMenu {
            Button("Delete Prompt", role: .destructive) {
                promptPendingDeletion = prompt
            }
        }
    }

    private func promptCell(_ prompt: Prompt) -> some View {
        Button {
            editingPrompt = EditingPrompt(id: prompt.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Row \(prompt.order + 1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if prompt.referenceImageFilename != nil {
                        Image(systemName: "photo").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Image(systemName: "pencil").font(.caption2).foregroundStyle(.tertiary)
                }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        let created = store.addRun(seed: seed, seedWasRandom: seedWasRandom)
        store.saveOrReport()
        // Persist the pending records first, then submit to the shared queue.
        coordinator.enqueue(created.jobs, for: store)
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
