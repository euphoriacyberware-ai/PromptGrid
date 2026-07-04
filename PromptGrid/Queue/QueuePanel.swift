//
//  QueuePanel.swift
//  PromptGrid
//
//  The queue popover (Specification §8), backed directly by DrawThingsQueue's
//  published state: what's generating now, the reorderable/cancellable pending
//  list, errors needing attention with retry, and pause/resume.
//

import SwiftUI
import PromptGridCore

/// Toolbar button with a pending-count badge that opens the queue popover.
struct QueueToolbarButton: View {
    @ObservedObject var queue: DrawThingsQueue
    @State private var isPresented = false

    private var pendingCount: Int {
        queue.pendingRequests.count + (queue.currentRequest != nil ? 1 : 0)
    }

    var body: some View {
        Button { isPresented = true } label: {
            Label("Queue", systemImage: "square.stack.3d.up")
        }
        .overlay(alignment: .topTrailing) {
            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .font(.caption2).bold()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.red, in: Capsule())
                    .foregroundStyle(.white)
                    .offset(x: 8, y: -8)
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            QueuePanel(queue: queue).frame(width: 360, height: 460)
        }
    }
}

/// A slim, always-visible banner surfacing paused/error state so generation
/// problems aren't hidden behind the queue popover.
struct GenerationStatusBanner: View {
    @ObservedObject var queue: DrawThingsQueue

    var body: some View {
        if queue.isPaused {
            banner(.orange, "pause.circle.fill",
                   queue.lastError ?? "Generation paused.",
                   actionTitle: "Resume") { queue.resume() }
        } else if let latest = queue.errors.last {
            banner(.red, "exclamationmark.triangle.fill",
                   "Generation failed: \((latest.underlyingError as NSError).localizedDescription)",
                   actionTitle: "Dismiss") { queue.clearErrors() }
        }
    }

    private func banner(_ color: Color, _ symbol: String, _ text: String,
                        actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.caption).lineLimit(2)
            Spacer()
            Button(actionTitle, action: action).font(.caption)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(color.opacity(0.12))
    }
}

struct QueuePanel: View {
    @ObservedObject var queue: DrawThingsQueue

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                if queue.isPaused {
                    pausedBanner
                }
                generatingSection
                pendingSection
                errorSection
                if isEmpty {
                    Text("The queue is empty.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowSeparator(.hidden)
                }
            }
#if os(macOS)
            .listStyle(.inset)
#else
            .listStyle(.insetGrouped)
#endif
        }
    }

    private var isEmpty: Bool {
        queue.currentRequest == nil && queue.pendingRequests.isEmpty && queue.errors.isEmpty
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Queue").font(.headline)
            Spacer()
            if queue.isProcessing || !queue.pendingRequests.isEmpty {
                Button(queue.isPaused ? "Resume" : "Pause") {
                    queue.isPaused ? queue.resume() : queue.pause()
                }
            }
        }
        .padding()
    }

    // MARK: Sections

    @ViewBuilder
    private var pausedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text("Paused").bold()
                if let error = queue.lastError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Resume") { queue.resume() }
        }
    }

    @ViewBuilder
    private var generatingSection: some View {
        if let current = queue.currentRequest {
            Section("Generating now") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(current.name).font(.subheadline).lineLimit(2)
                        Spacer()
                        Button {
                            _ = queue.cancel(id: current.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Cancel this generation")
                    }
                    if let progress = queue.currentProgress {
                        CurrentProgressView(progress: progress)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if !queue.pendingRequests.isEmpty {
            Section("Pending") {
                ForEach(queue.pendingRequests) { request in
                    HStack {
                        Text(request.name).lineLimit(2)
                        Spacer()
                        Button {
                            _ = queue.cancel(id: request.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { source, destination in
                    queue.moveRequests(from: source, to: destination)
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if !queue.errors.isEmpty {
            Section("Needs attention") {
                ForEach(queue.errors) { error in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(error.request.name).font(.subheadline).lineLimit(2)
                        Text((error.underlyingError as NSError).localizedDescription)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        HStack {
                            Text("Attempt \(queue.retryCount(for: error.id))/\(queue.maxRetries)")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Spacer()
                            Button("Retry") { _ = queue.retry(error.id) }
                                .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// Observes the in-flight progress object so the bar updates step by step.
private struct CurrentProgressView: View {
    @ObservedObject var progress: GenerationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let preview = progress.previewImage {
                platformImage(preview)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            ProgressView(value: progress.progressFraction)
            Text("\(String(describing: progress.stage)) · \(progress.progressPercentage)%")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func platformImage(_ image: PlatformImage) -> Image {
#if os(macOS)
        Image(nsImage: image)
#else
        Image(uiImage: image)
#endif
    }
}
