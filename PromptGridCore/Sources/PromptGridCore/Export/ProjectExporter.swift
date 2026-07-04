//
//  ProjectExporter.swift
//  PromptGridCore
//
//  Export orchestration (Specification §11): pick the completed cells matching a
//  filter, compute collision-free filenames, assemble XMP metadata, and write a
//  single flat folder of PNGs with no sidecars.
//
//  Split into `plan(...)` (runs on the caller's actor; needs image data) and
//  `write(...)` (pure, safe to run off the main thread) so a large export
//  doesn't block the UI.
//

import Foundation

public enum ProjectExporter {

    /// One completed, exportable cell.
    public struct Entry: Sendable {
        public let prompt: Prompt
        public let run: Run
        public let job: GenerationJob
    }

    /// A fully-prepared file to write: image bytes + metadata + final filename.
    public struct Unit: Sendable {
        public let filename: String
        public let imageData: Data
        public let metadata: PNGMetadataWriter.Payload
    }

    // MARK: Selection / counts

    /// Completed cells with an image, matching the filter, in row-major order.
    public static func entries(in project: Project, filter: ExportFilter) -> [Entry] {
        var result: [Entry] = []
        let orderedPrompts = project.prompts.sorted { $0.order < $1.order }
        let orderedRuns = project.runs.sorted { $0.index < $1.index }
        for prompt in orderedPrompts {
            for run in orderedRuns {
                guard let job = prompt.jobs[run.id],
                      job.status == .completed,
                      job.imageFilename != nil,
                      filter.includes(job.rank) else { continue }
                result.append(Entry(prompt: prompt, run: run, job: job))
            }
        }
        return result
    }

    public static func count(in project: Project, filter: ExportFilter) -> Int {
        entries(in: project, filter: filter).count
    }

    // MARK: Plan

    /// Build the write units. `imageData` supplies the full-resolution bytes for
    /// a job (Phase 11 will materialize iCloud placeholders inside this closure).
    public static func plan(
        project: Project,
        filter: ExportFilter,
        creatorTool: String,
        imageData: (GenerationJob) -> Data?
    ) -> [Unit] {
        var usedNames = Set<String>()
        var units: [Unit] = []
        for entry in entries(in: project, filter: filter) {
            guard let data = imageData(entry.job) else { continue }
            let name = uniqueFilename(for: entry, existing: &usedNames)
            let payload = ExportMetadata.payload(for: entry, project: project, creatorTool: creatorTool)
            units.append(Unit(filename: name, imageData: data, metadata: payload))
        }
        return units
    }

    // MARK: Write

    /// Write prepared units into `directory`. Pure — safe off the main actor.
    @discardableResult
    public static func write(
        _ units: [Unit],
        to directory: URL,
        progress: ((_ completed: Int, _ total: Int) -> Void)? = nil
    ) throws -> Int {
        var written = 0
        for unit in units {
            let data = try PNGMetadataWriter.embedding(unit.metadata, into: unit.imageData)
            try data.write(to: directory.appendingPathComponent(unit.filename), options: .atomic)
            written += 1
            progress?(written, units.count)
        }
        return written
    }

    // MARK: Filenames

    /// `{rowIndex}_{slug}_run{n}{_rank}.png` (Specification §11). Rank suffix
    /// omitted for plain candidate; collisions get `-2`, `-3`, …
    static func uniqueFilename(for entry: Entry, existing: inout Set<String>) -> String {
        let row = String(format: "%02d", entry.prompt.order + 1)
        let slug = slugify(entry.job.resolvedPrompt.isEmpty ? entry.prompt.text : entry.job.resolvedPrompt)
        let rankSuffix: String
        switch entry.job.rank {
        case .final: rankSuffix = "_final"
        case .shortlisted: rankSuffix = "_shortlisted"
        case .candidate, .none: rankSuffix = ""
        }
        let base = "\(row)_\(slug)_run\(entry.run.index)\(rankSuffix)"

        var candidate = "\(base).png"
        var counter = 2
        while existing.contains(candidate) {
            candidate = "\(base)-\(counter).png"
            counter += 1
        }
        existing.insert(candidate)
        return candidate
    }

    /// Lowercase, alphanumerics kept, everything else collapsed to single hyphens.
    static func slugify(_ text: String, maxLength: Int = 40) -> String {
        var result = ""
        var pendingHyphen = false
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingHyphen && !result.isEmpty { result.append("-") }
                pendingHyphen = false
                result.append(character)
            } else {
                pendingHyphen = true
            }
        }
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "untitled" : result
    }
}
