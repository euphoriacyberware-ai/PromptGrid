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
        let projectSlug = slugify(project.name)
        for entry in entries(in: project, filter: filter) {
            guard let data = imageData(entry.job) else { continue }
            let name = uniqueFilename(for: entry, projectSlug: projectSlug, existing: &usedNames)
            let payload = ExportMetadata.payload(for: entry, project: project, creatorTool: creatorTool)
            units.append(Unit(filename: name, imageData: data, metadata: payload))
        }
        return units
    }

    // MARK: Single image

    /// Build the fully-prepared export bytes (image + embedded XMP metadata) and a
    /// suggested filename for one completed job — the per-cell "Export Image…"
    /// action. Nil if the job's prompt/run can't be found in the project.
    public static func singleImage(project: Project, job: GenerationJob,
                                   imageData: Data, creatorTool: String) throws -> (filename: String, data: Data)? {
        guard let prompt = project.prompts.first(where: { $0.id == job.promptID }),
              let run = project.runs.first(where: { $0.id == job.runID }) else { return nil }
        let entry = Entry(prompt: prompt, run: run, job: job)
        var used = Set<String>()
        let filename = uniqueFilename(for: entry, projectSlug: slugify(project.name), existing: &used)
        let payload = ExportMetadata.payload(for: entry, project: project, creatorTool: creatorTool)
        let data = try PNGMetadataWriter.embedding(payload, into: imageData)
        return (filename, data)
    }

    // MARK: Prompts (JSON) export

    /// Prompt rows to export, in row order. "All" includes every prompt — even
    /// ones that have never generated an image (a prompt row is worth exporting
    /// on its own). A rank filter, being about generated images, keeps only rows
    /// with at least one completed image of that rank.
    public static func promptEntries(in project: Project, filter: ExportFilter) -> [Prompt] {
        let ordered = project.prompts.sorted { $0.order < $1.order }
        switch filter {
        case .all:
            return ordered
        case .finalOnly, .finalAndShortlisted:
            return ordered.filter { prompt in
                prompt.jobs.values.contains {
                    $0.status == .completed && $0.imageFilename != nil && filter.includes($0.rank)
                }
            }
        }
    }

    public static func promptCount(in project: Project, filter: ExportFilter) -> Int {
        promptEntries(in: project, filter: filter).count
    }

    /// Pretty-printed JSON of the filtered prompt rows (templates, negative
    /// prompts, and their configuration) — a reusable prompt list.
    public static func promptsJSON(project: Project, filter: ExportFilter, exportedAt: Date) throws -> Data {
        let document = PromptsDocument(
            project: project.name,
            exportedAt: exportedAt,
            filter: filter.rawValue,
            prompts: promptEntries(in: project, filter: filter).map { prompt in
                PromptsDocument.Item(
                    row: prompt.order + 1,
                    title: prompt.title,
                    prompt: prompt.text,
                    negativePrompt: prompt.negativePrompt,
                    notes: prompt.notes,
                    referenceImage: prompt.referenceImageFilename,
                    configuration: prompt.settings
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    struct PromptsDocument: Codable {
        let project: String
        let exportedAt: Date
        let filter: String
        let prompts: [Item]

        struct Item: Codable {
            let row: Int
            let title: String?
            let prompt: String
            let negativePrompt: String
            let notes: String?
            let referenceImage: String?
            let configuration: DrawThingsConfigurationDTO
        }
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

    /// `{rowIndex}_{projectSlug}_{slug}_run{n}{_rank}.png` (Specification §11).
    /// Rank suffix omitted for plain candidate; collisions get `-2`, `-3`, …
    static func uniqueFilename(for entry: Entry, projectSlug: String, existing: inout Set<String>) -> String {
        let row = String(format: "%02d", entry.prompt.order + 1)
        // Prefer the prompt's title; fall back to the (resolved) prompt text.
        let title = entry.prompt.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = (title?.isEmpty == false)
            ? title!
            : (entry.job.resolvedPrompt.isEmpty ? entry.prompt.text : entry.job.resolvedPrompt)
        let slug = slugify(source)
        let rankSuffix: String
        switch entry.job.rank {
        case .final: rankSuffix = "_final"
        case .shortlisted: rankSuffix = "_shortlisted"
        case .candidate, .none: rankSuffix = ""
        }
        let base = "\(row)_\(projectSlug)_\(slug)_run\(entry.run.index)\(rankSuffix)"

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
    public static func slugify(_ text: String, maxLength: Int = 40) -> String {
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
