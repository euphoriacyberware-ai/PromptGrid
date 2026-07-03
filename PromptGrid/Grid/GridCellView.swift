//
//  GridCellView.swift
//  PromptGrid
//
//  One grid cell: a run's result for a prompt. Static thumbnail + rank badge
//  (Specification §6, §10). Rich interactions — inspector, lightbox, generate/
//  retry — arrive in Phase 8; this is display-only.
//

import SwiftUI
import PromptGridCore

struct GridCellView: View {
    let job: GenerationJob?
    /// Thumbnail bytes for a completed job, if present in the package.
    let thumbnailData: Data?
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary.opacity(0.4))
            .frame(width: size, height: size)
            .overlay { content }
            .overlay(alignment: .topTrailing) { rankBadge }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator, style: strokeStyle)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        switch job?.status {
        case nil:
            // Empty cell — never generated. Show the raw template state (§5): a
            // simple placeholder here; the inspector shows details in Phase 8.
            Image(systemName: "plus")
                .foregroundStyle(.tertiary)
                .font(.title2)
        case .completed:
            if let thumbnailData, let image = PlatformImageView(data: thumbnailData) {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary).font(.title2)
            }
        case .pending:
            Image(systemName: "clock").foregroundStyle(.secondary).font(.title2)
        case .generating:
            ProgressView()
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.title2)
        case .cancelled:
            Image(systemName: "slash.circle").foregroundStyle(.secondary).font(.title2)
        }
    }

    private var strokeStyle: StrokeStyle {
        // Empty cells get a dashed border to read as "not yet generated".
        job == nil ? StrokeStyle(lineWidth: 1, dash: [4]) : StrokeStyle(lineWidth: 1)
    }

    @ViewBuilder
    private var rankBadge: some View {
        switch job?.rank {
        case .final:
            badge(systemName: "star.fill", color: .yellow)
        case .shortlisted:
            badge(systemName: "star", color: .yellow)
        case .candidate, nil:
            EmptyView()
        }
    }

    private func badge(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.caption)
            .foregroundStyle(color)
            .padding(4)
            .background(.thinMaterial, in: Circle())
            .padding(4)
    }
}

/// Cross-platform `Data` -> SwiftUI `Image`.
private func PlatformImageView(data: Data) -> Image? {
#if os(macOS)
    guard let image = NSImage(data: data) else { return nil }
    return Image(nsImage: image)
#else
    guard let image = UIImage(data: data) else { return nil }
    return Image(uiImage: image)
#endif
}
