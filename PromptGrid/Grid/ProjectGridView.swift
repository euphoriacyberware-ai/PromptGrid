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

    @State private var promptPendingDeletion: Prompt?
    @State private var runPendingDeletion: Run?
    @State private var isPresentingSeedPicker = false

    private let promptColumnWidth: CGFloat = 260
    private let cellSize: CGFloat = 120
    private let spacing: CGFloat = 8

    private var runs: [Run] { store.project.runs }
    private var prompts: [Prompt] { store.project.prompts }

    var body: some View {
        Group {
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
                let job = prompt.jobs[run.id]
                GridCellView(
                    job: job,
                    thumbnailData: job.flatMap { store.thumbnailData(for: $0) },
                    size: cellSize
                )
            }
        }
        .contextMenu {
            Button("Delete Prompt", role: .destructive) {
                promptPendingDeletion = prompt
            }
        }
    }

    private func promptCell(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Row \(prompt.order + 1)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if prompt.text.isEmpty {
                Text("Empty prompt")
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                // Static, truncated by default (§13); live editing is Phase 7.
                Text(prompt.text)
                    .lineLimit(4)
                    .truncationMode(.tail)
            }
        }
        .frame(width: promptColumnWidth, height: cellSize, alignment: .topLeading)
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
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
        store.addRun(seed: seed, seedWasRandom: seedWasRandom)
        store.saveOrReport()
        // Phase 6 wires the created jobs to the global DrawThingsQueue.
    }

    private func deleteRun(_ run: Run) {
        // Phase 6 cancels in-flight jobs (store.cancellableJobIDs) in the queue
        // before this removal, per §7 step 1.
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
