//
//  LightboxView.swift
//  PromptGrid
//
//  The lightbox (Specification §9): the image large, the same CellInspector in a
//  right-hand panel, and 2D navigation mirroring the grid axes — left/right move
//  across runs (row fixed), up/down across prompts (column fixed). Arrow keys on
//  Mac/iPad; four edge chevrons everywhere. Navigation always moves to the
//  adjacent cell regardless of its status.
//

import SwiftUI
import PromptGridCore

struct LightboxView: View {
    let store: ProjectStore
    @State var current: CellRef
    let onClose: () -> Void

#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var prompts: [Prompt] { store.project.prompts }
    private var runs: [Run] { store.project.runs }
    private var promptIndex: Int? { prompts.firstIndex { $0.id == current.promptID } }
    private var runIndex: Int? { runs.firstIndex { $0.id == current.runID } }

    private var prompt: Prompt? { prompts.first { $0.id == current.promptID } }
    private var job: GenerationJob? { prompt?.jobs[current.runID] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            content
        }
        .frame(minWidth: 700, minHeight: 480)
#if os(macOS)
        .background(.background)
#endif
    }

    private var topBar: some View {
        HStack {
            if let prompt, let run = runs.first(where: { $0.id == current.runID }) {
                Text("Row \(prompt.order + 1) · Run \(run.index)").font(.headline)
            }
            Spacer()
            Button("Done", action: onClose).keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
#if os(macOS)
        HStack(spacing: 0) { imagePane; Divider(); inspectorPane }
#else
        if horizontalSizeClass == .regular {
            HStack(spacing: 0) { imagePane; Divider(); inspectorPane }
        } else {
            VStack(spacing: 0) { imagePane.frame(maxHeight: 360); Divider(); inspectorPane }
        }
#endif
    }

    private var inspectorPane: some View {
        CellInspector(store: store, cell: current)
            .frame(width: inspectorWidth)
    }

    private var inspectorWidth: CGFloat? {
#if os(iOS)
        horizontalSizeClass == .regular ? 340 : nil
#else
        340
#endif
    }

    // MARK: Image pane with edge chevrons

    private var imagePane: some View {
        ZStack {
            Color.black.opacity(0.03)
            imageOrState
                .padding(40)

            // Edge chevrons (touch + everywhere).
            chevron("chevron.left", disabled: (runIndex ?? 0) <= 0) { move(dPrompt: 0, dRun: -1) }
                .frame(maxWidth: .infinity, alignment: .leading)
            chevron("chevron.right", disabled: (runIndex ?? 0) >= runs.count - 1) { move(dPrompt: 0, dRun: 1) }
                .frame(maxWidth: .infinity, alignment: .trailing)
            chevron("chevron.up", disabled: (promptIndex ?? 0) <= 0) { move(dPrompt: -1, dRun: 0) }
                .frame(maxHeight: .infinity, alignment: .top)
            chevron("chevron.down", disabled: (promptIndex ?? 0) >= prompts.count - 1) { move(dPrompt: 1, dRun: 0) }
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .onKeyPress(.leftArrow) { move(dPrompt: 0, dRun: -1); return .handled }
        .onKeyPress(.rightArrow) { move(dPrompt: 0, dRun: 1); return .handled }
        .onKeyPress(.upArrow) { move(dPrompt: -1, dRun: 0); return .handled }
        .onKeyPress(.downArrow) { move(dPrompt: 1, dRun: 0); return .handled }
    }

    @ViewBuilder
    private var imageOrState: some View {
        switch job?.status {
        case .completed:
            if let data = job.flatMap({ store.imageData(for: $0) ?? store.thumbnailData(for: $0) }),
               let image = platformImage(data) {
                image.resizable().scaledToFit()
            } else {
                stateView("photo", "Image unavailable")
            }
        case nil:
            stateView("square.dashed", "Empty — use Generate in the inspector")
        case .pending:
            stateView("clock", "Pending")
        case .generating:
            ProgressView("Generating…")
        case .failed:
            stateView("exclamationmark.triangle.fill", "Failed — use Retry in the inspector")
        case .cancelled:
            stateView("slash.circle", "Cancelled")
        }
    }

    private func stateView(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 48)).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func chevron(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .padding(10)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }

    // MARK: Navigation

    private func move(dPrompt: Int, dRun: Int) {
        guard let pi = promptIndex, let ri = runIndex else { return }
        let np = pi + dPrompt, nr = ri + dRun
        guard prompts.indices.contains(np), runs.indices.contains(nr) else { return }
        current = CellRef(promptID: prompts[np].id, runID: runs[nr].id)
    }

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
