//
//  CellInspector.swift
//  PromptGrid
//
//  The single inspector component (Specification §9), placed in two containers:
//  the persistent sidebar (single-click) and the lightbox's right panel
//  (double-click). Shows status, the resolved prompts (or the raw template for
//  an empty cell), a compact settings table, the rank control, timestamp, and
//  the Generate / Retry actions.
//

import SwiftUI
import PromptGridCore

/// Identifies one grid cell.
struct CellRef: Identifiable, Hashable {
    let promptID: UUID
    let runID: UUID
    var id: String { "\(promptID.uuidString)-\(runID.uuidString)" }
}

struct CellInspector: View {
    let store: ProjectStore
    let cell: CellRef
    @EnvironmentObject private var coordinator: GenerationCoordinator
    @State private var isConfirmingDelete = false

    private var prompt: Prompt? { store.project.prompts.first { $0.id == cell.promptID } }
    private var run: Run? { store.project.runs.first { $0.id == cell.runID } }
    private var job: GenerationJob? { prompt?.jobs[cell.runID] }

    /// Settings that apply: the frozen snapshot if generated, else the prompt's
    /// current settings (what *would* be used).
    private var settings: DrawThingsConfigurationDTO? { job?.settingsSnapshot ?? prompt?.settings }
    private var seed: Int? { job?.seedUsed ?? run?.seed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusRow
                promptSection
                settingsSection
                if job?.status == .completed { rankSection; timestampSection }
                actions
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let prompt, let run {
                Text("Row \(prompt.order + 1) · Run \(run.index)").font(.headline)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon).foregroundStyle(statusColor)
            Text(statusText).foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var promptSection: some View {
        let isFrozen = job != nil
        VStack(alignment: .leading, spacing: 8) {
            labeledText(isFrozen ? "Resolved Prompt" : "Prompt (template)",
                        job?.resolvedPrompt ?? prompt?.text ?? "")
            let negative = job?.resolvedNegativePrompt ?? prompt?.negativePrompt ?? ""
            if !negative.isEmpty {
                labeledText(isFrozen ? "Resolved Negative" : "Negative (template)", negative)
            }
        }
    }

    @ViewBuilder
    private var settingsSection: some View {
        if let settings {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings").font(.subheadline).bold()
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    settingRow("Model", settings.model)
                    settingRow("Sampler", samplerName(settings.sampler))
                    settingRow("Steps", "\(settings.steps)")
                    settingRow("Size", "\(settings.width)×\(settings.height)")
                    settingRow("Guidance", String(format: "%.1f", settings.guidanceScale))
                    settingRow("Shift", trimFloat(settings.shift))
                    settingRow("Seed", seed.map(String.init) ?? "—")
                    if let upscaler = settings.upscaler, !upscaler.isEmpty {
                        settingRow("Upscaler", upscaler)
                    }
                    if let face = settings.faceRestoration, !face.isEmpty {
                        settingRow("Face Restoration", face)
                    }
                }
                .font(.caption)

                if !settings.loras.isEmpty {
                    listRows("LoRAs", settings.loras.map { "\($0.file) · \(trimFloat($0.weight))" })
                }
                if !settings.controls.isEmpty {
                    listRows("ControlNets", settings.controls.map { "\($0.file) · \(trimFloat($0.weight))" })
                }
            }
        }
    }

    private var rankSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rank").font(.subheadline).bold()
            Picker("Rank", selection: rankBinding) {
                Text("Candidate").tag(CellRank.candidate)
                Text("Shortlisted").tag(CellRank.shortlisted)
                Text("Final").tag(CellRank.final)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var timestampSection: some View {
        if let completedAt = job?.completedAt {
            Text("Generated \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch job?.status {
            case nil:
                Button("Generate", systemImage: "wand.and.stars", action: generate)
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.isConfigured)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry", systemImage: "arrow.clockwise", action: retry)
                        .buttonStyle(.borderedProminent)
                        .disabled(!coordinator.isConfigured)
                }
            default:
                EmptyView()
            }

            if job != nil {
                Button("Delete Image…", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .confirmationDialog("Delete Image?", isPresented: $isConfirmingDelete) {
                    Button("Delete Image", role: .destructive, action: deleteImage)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This deletes the generated image. The cell becomes empty and can be generated again. This can’t be undone.")
                }
            }
        }
    }

    // MARK: Actions

    private func generate() {
        guard let job = store.generateCell(promptID: cell.promptID, runID: cell.runID) else { return }
        store.saveOrReport()
        coordinator.enqueue([job], for: store)
    }

    private func retry() {
        guard let job else { return }
        coordinator.retry(job, in: store)
    }

    private func deleteImage() {
        store.deleteCell(promptID: cell.promptID, runID: cell.runID)
        store.saveOrReport()
    }

    private var rankBinding: Binding<CellRank> {
        Binding(
            get: { job?.rank ?? .candidate },
            set: { newValue in
                guard let job else { return }
                store.setRank(jobID: job.id, to: newValue)
                store.saveOrReport()
            }
        )
    }

    // MARK: Helpers

    private func labeledText(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(text.isEmpty ? "—" : text).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    /// A labeled list (LoRAs / ControlNets), one entry per line.
    private func listRows(_ label: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Drop trailing zeros: 3.0 → "3", 1.15 → "1.15".
    private func trimFloat(_ value: Float) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    private func samplerName(_ raw: Int8) -> String {
        SamplerType(rawValue: raw).map { String(describing: $0) } ?? "\(raw)"
    }

    private var statusText: String {
        switch job?.status {
        case nil: return "Not generated"
        case .pending: return "Pending"
        case .generating: return "Generating…"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var statusIcon: String {
        switch job?.status {
        case nil: return "square.dashed"
        case .pending: return "clock"
        case .generating: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "slash.circle"
        }
    }

    private var statusColor: Color {
        switch job?.status {
        case .completed: return .green
        case .failed: return .orange
        case .cancelled: return .secondary
        default: return .secondary
        }
    }
}
