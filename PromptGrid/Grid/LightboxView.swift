//
//  LightboxView.swift
//  PromptGrid
//
//  Full-screen image viewer (Specification §9, adapted). The image gets the whole
//  surface — zoomable from Fit up to full resolution via buttons or pinch, and
//  pannable when zoomed. The detailed inspector lives in the sidebar
//  (single-click); here a slim bar carries just the essential actions (rank,
//  generate/retry, delete). 2D navigation mirrors the grid axes: left/right across
//  runs, up/down across prompts — arrow keys and four edge chevrons.
//

import SwiftUI
import PromptGridCore

struct LightboxView: View {
    let store: ProjectStore
    @State var current: CellRef
    let onClose: () -> Void

    @EnvironmentObject private var coordinator: GenerationCoordinator
    @State private var zoom: CGFloat = 1          // multiplier on the fit scale
    @GestureState private var pinch: CGFloat = 1
    @State private var isConfirmingDelete = false

    private let maxZoom: CGFloat = 8

    private var prompts: [Prompt] { store.project.prompts }
    private var runs: [Run] { store.project.runs }
    private var promptIndex: Int? { prompts.firstIndex { $0.id == current.promptID } }
    private var runIndex: Int? { runs.firstIndex { $0.id == current.runID } }
    private var prompt: Prompt? { prompts.first { $0.id == current.promptID } }
    private var run: Run? { runs.first { $0.id == current.runID } }
    private var job: GenerationJob? { prompt?.jobs[current.runID] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            imageArea
            Divider()
            bottomBar
        }
#if os(macOS)
        .frame(minWidth: 960, idealWidth: 1200, minHeight: 720, idealHeight: 900)
        .background(.background)
#endif
        .onChange(of: current) { _, _ in zoom = 1 }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            if let prompt, let run {
                Text("Row \(prompt.order + 1) · Run \(run.index)").font(.headline)
            }
            statusBadge
            Spacer()
            Button("Done", action: onClose).keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var statusBadge: some View {
        Group {
            switch job?.status {
            case .completed: Label("Completed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Label("Failed", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .generating: Label("Generating", systemImage: "arrow.triangle.2.circlepath")
            case .pending: Label("Pending", systemImage: "clock")
            case .cancelled: Label("Cancelled", systemImage: "slash.circle")
            case nil: Label("Empty", systemImage: "square.dashed")
            }
        }
        .font(.caption).labelStyle(.titleAndIcon)
    }

    // MARK: Image area

    private var imageArea: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.06)
                imageContent(container: geo.size)

                chevron("chevron.left", disabled: (runIndex ?? 0) <= 0) { move(dPrompt: 0, dRun: -1) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                chevron("chevron.right", disabled: (runIndex ?? 0) >= runs.count - 1) { move(dPrompt: 0, dRun: 1) }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                chevron("chevron.up", disabled: (promptIndex ?? 0) <= 0) { move(dPrompt: -1, dRun: 0) }
                    .frame(maxHeight: .infinity, alignment: .top)
                chevron("chevron.down", disabled: (promptIndex ?? 0) >= prompts.count - 1) { move(dPrompt: 1, dRun: 0) }
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .onKeyPress(.leftArrow) { move(dPrompt: 0, dRun: -1); return .handled }
        .onKeyPress(.rightArrow) { move(dPrompt: 0, dRun: 1); return .handled }
        .onKeyPress(.upArrow) { move(dPrompt: -1, dRun: 0); return .handled }
        .onKeyPress(.downArrow) { move(dPrompt: 1, dRun: 0); return .handled }
    }

    @ViewBuilder
    private func imageContent(container: CGSize) -> some View {
        switch job?.status {
        case .completed:
            if let data = imageData, let loaded = loadImage(data) {
                zoomableImage(loaded.image, pixelSize: loaded.size, container: container)
            } else {
                stateView("photo", "Image unavailable")
            }
        case nil:
            VStack(spacing: 14) {
                stateView("square.dashed", "Empty cell")
                Button("Generate", systemImage: "wand.and.stars", action: generate)
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.isConfigured)
            }
        case .pending:
            stateView("clock", "Pending")
        case .generating:
            ProgressView("Generating…")
        case .failed(let message):
            VStack(spacing: 14) {
                stateView("exclamationmark.triangle.fill", message)
                Button("Retry", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.isConfigured)
            }
        case .cancelled:
            stateView("slash.circle", "Cancelled")
        }
    }

    private func zoomableImage(_ image: Image, pixelSize: CGSize, container: CGSize) -> some View {
        let fit = min(container.width / max(pixelSize.width, 1), container.height / max(pixelSize.height, 1))
        let effective = min(max(zoom * pinch, 1), maxZoom)
        let display = CGSize(width: pixelSize.width * fit * effective,
                             height: pixelSize.height * fit * effective)
        return ScrollView([.horizontal, .vertical]) {
            image
                .resizable()
                .interpolation(.high)
                .frame(width: display.width, height: display.height)
                .frame(minWidth: container.width, minHeight: container.height) // center when small
        }
        .scrollDisabled(effective <= 1.001)
        .gesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = min(max(zoom * value.magnification, 1), maxZoom) }
        )
    }

    private func stateView(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 360)
        }
        .padding()
    }

    private func chevron(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2).padding(10)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain).padding(8).disabled(disabled).opacity(disabled ? 0.25 : 1)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 14) {
            zoomControls
            Spacer()
            contextActions
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    @ViewBuilder
    private var zoomControls: some View {
        if job?.status == .completed {
            HStack(spacing: 6) {
                Button("Fit") { zoom = 1 }.disabled(zoom == 1)
                Button { zoom = max(zoom / 1.5, 1) } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(zoom <= 1)
                Text("\(Int((zoom) * 100))%").font(.caption.monospacedDigit())
                    .frame(width: 46)
                Button { zoom = min(zoom * 1.5, maxZoom) } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(zoom >= maxZoom)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var contextActions: some View {
        if job?.status == .completed {
            Picker("Rank", selection: rankBinding) {
                Text("Candidate").tag(CellRank.candidate)
                Text("Shortlisted").tag(CellRank.shortlisted)
                Text("Final").tag(CellRank.final)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 280)
        }
        if job != nil {
            Button(role: .destructive) { isConfirmingDelete = true } label: {
                Image(systemName: "trash")
            }
            .confirmationDialog("Delete Image?", isPresented: $isConfirmingDelete) {
                Button("Delete Image", role: .destructive, action: deleteImage)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the generated image. The cell becomes empty and can be generated again. This can’t be undone.")
            }
        }
    }

    // MARK: Actions

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

    private func generate() {
        guard let job = store.generateCell(promptID: current.promptID, runID: current.runID) else { return }
        store.saveOrReport()
        coordinator.enqueue([job], for: store)
    }

    private func retry() {
        guard let job else { return }
        coordinator.retry(job, in: store)
    }

    private func deleteImage() {
        store.deleteCell(promptID: current.promptID, runID: current.runID)
        store.saveOrReport()
    }

    // MARK: Navigation

    private func move(dPrompt: Int, dRun: Int) {
        guard let pi = promptIndex, let ri = runIndex else { return }
        let np = pi + dPrompt, nr = ri + dRun
        guard prompts.indices.contains(np), runs.indices.contains(nr) else { return }
        current = CellRef(promptID: prompts[np].id, runID: runs[nr].id)
    }

    private var imageData: Data? {
        job.flatMap { store.imageData(for: $0) ?? store.thumbnailData(for: $0) }
    }

    private func loadImage(_ data: Data) -> (image: Image, size: CGSize)? {
#if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return (Image(nsImage: image), image.size)
#else
        guard let image = UIImage(data: data) else { return nil }
        return (Image(uiImage: image), image.size)
#endif
    }
}
