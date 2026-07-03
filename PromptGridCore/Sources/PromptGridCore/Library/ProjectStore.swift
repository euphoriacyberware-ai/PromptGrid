//
//  ProjectStore.swift
//  PromptGridCore
//
//  The observable editing model for one open project. Holds a mutable `Project`,
//  persists changes back into the `.pgproj` package (preserving image files via
//  the retained `ProjectPackage`), and exposes the grid mutations. Business rules
//  that must stay invariant — e.g. contiguous prompt `order` — live here, not in
//  the views.
//

import Foundation
import Observation

@MainActor
@Observable
public final class ProjectStore {

    public let url: URL
    public private(set) var project: Project
    /// Surfaced to the UI when a save fails.
    public var lastError: String?

    private let package: ProjectPackage

    // MARK: Init

    /// Open the package at `url`.
    public init(contentsOf url: URL) throws {
        self.url = url
        self.package = try FileCoordination.read(at: url) { url in
            let wrapper = try FileWrapper(url: url, options: .immediate)
            return try ProjectPackage(readingFrom: wrapper)
        }
        self.project = package.project
    }

    /// In-memory store, for tests and previews.
    public init(url: URL, package: ProjectPackage) {
        self.url = url
        self.package = package
        self.project = package.project
    }

    // MARK: Persistence

    /// Write the current project back to disk (updating `modifiedAt`).
    public func save() throws {
        project.modifiedAt = Date()
        package.updateProject(project)
        let wrapper = try package.fileWrapper()
        try FileCoordination.write(wrapper, to: url)
    }

    /// Save, routing any failure to `lastError` instead of throwing — convenient
    /// for call sites in view actions.
    public func saveOrReport() {
        do { try save() }
        catch { lastError = error.localizedDescription }
    }

    // MARK: Prompt (row) mutations

    /// Append a new empty prompt seeded with the project's default settings.
    @discardableResult
    public func addPrompt() -> Prompt {
        let prompt = Prompt(
            settings: project.defaultSettings,
            order: project.prompts.count
        )
        project.prompts.append(prompt)
        return prompt
    }

    /// Remove a prompt, delete any of its cell images from the package, and keep
    /// `order` contiguous.
    public func removePrompt(id: UUID) {
        guard let index = project.prompts.firstIndex(where: { $0.id == id }) else { return }
        let removed = project.prompts.remove(at: index)

        for job in removed.jobs.values {
            if let name = job.imageFilename { package.removeImage(named: name) }
            if let name = job.thumbnailFilename { package.removeThumbnail(named: name) }
        }
        if let reference = removed.referenceImageFilename {
            package.removeReference(named: reference)
        }

        renumberPrompts()
    }

    /// Reorder rows (drag-to-reorder in the grid).
    public func movePrompts(fromOffsets: IndexSet, toOffset: Int) {
        project.prompts.move(fromOffsets: fromOffsets, toOffset: toOffset)
        renumberPrompts()
    }

    private func renumberPrompts() {
        for index in project.prompts.indices {
            project.prompts[index].order = index
        }
    }

    // MARK: Run (column) mutations

    /// Create a run and, for every existing prompt, a frozen `pending` job
    /// (Specification §7). Wildcards are resolved *now* and frozen; the settings
    /// snapshot and seed are frozen too (§4, §5). Returns the run plus the jobs
    /// that a caller should enqueue — the actual queue submission is wired up in
    /// Phase 6.
    @discardableResult
    public func addRun(seed: Int, seedWasRandom: Bool) -> (run: Run, jobs: [GenerationJob]) {
        let run = Run(index: project.runs.count + 1, seed: seed, seedWasRandom: seedWasRandom)
        project.runs.append(run)

        var created: [GenerationJob] = []
        for index in project.prompts.indices {
            let prompt = project.prompts[index]
            let job = GenerationJob(
                runID: run.id,
                promptID: prompt.id,
                status: .pending,
                seedUsed: seed,
                settingsSnapshot: prompt.settings,
                resolvedPrompt: WildcardResolver.resolve(prompt.text),
                resolvedNegativePrompt: WildcardResolver.resolve(prompt.negativePrompt)
            )
            project.prompts[index].jobs[run.id] = job
            created.append(job)
        }
        return (run, created)
    }

    /// Jobs in a run that are still in flight and must be cancelled in the queue
    /// *before* the run is removed (Specification §7, step 1).
    public func cancellableJobIDs(forRunID runID: UUID) -> [UUID] {
        project.prompts.flatMap { prompt -> [UUID] in
            guard let job = prompt.jobs[runID] else { return [] }
            switch job.status {
            case .pending, .generating: return [job.id]
            case .completed, .failed, .cancelled: return []
            }
        }
    }

    /// Number of completed images in a run — the `N` in the delete confirmation
    /// copy (Specification §7).
    public func completedImageCount(forRunID runID: UUID) -> Int {
        project.prompts.reduce(0) { count, prompt in
            count + (prompt.jobs[runID]?.status == .completed ? 1 : 0)
        }
    }

    /// Remove a run: delete its cell images from the package, drop its jobs from
    /// every prompt, remove the run record, and keep `index` contiguous
    /// (Specification §7, step 3). Cancel in-flight jobs in the queue *before*
    /// calling this.
    public func deleteRun(id runID: UUID) {
        for index in project.prompts.indices {
            guard let job = project.prompts[index].jobs[runID] else { continue }
            if let name = job.imageFilename { package.removeImage(named: name) }
            if let name = job.thumbnailFilename { package.removeThumbnail(named: name) }
            project.prompts[index].jobs[runID] = nil
        }
        project.runs.removeAll { $0.id == runID }
        renumberRuns()
    }

    private func renumberRuns() {
        for index in project.runs.indices {
            project.runs[index].index = index + 1
        }
    }

    // MARK: Results

    /// Apply a finished generation to its job. Returns `false` — writing nothing —
    /// if the job or its run no longer exists, which is the orphan-result guard
    /// (Specification §7, step 2): a result can arrive after its run was deleted.
    @discardableResult
    public func applyResult(jobID: UUID, imageData: Data, thumbnailData: Data,
                            completedAt: Date = Date()) -> Bool {
        guard let promptIndex = project.prompts.firstIndex(where: {
            $0.jobs.values.contains { $0.id == jobID }
        }) else { return false }

        guard var job = project.prompts[promptIndex].jobs.values.first(where: { $0.id == jobID })
        else { return false }

        // Orphan guard: the run may have been deleted while this was generating.
        guard project.runs.contains(where: { $0.id == job.runID }) else { return false }

        let imageName = "\(job.id).png"
        package.setImageData(imageData, named: imageName)
        package.setThumbnailData(thumbnailData, named: imageName)

        job.status = .completed
        job.rank = .candidate
        job.imageFilename = imageName
        job.thumbnailFilename = imageName
        job.completedAt = completedAt
        project.prompts[promptIndex].jobs[job.runID] = job
        return true
    }

    // MARK: Cell assets

    public func thumbnailData(for job: GenerationJob) -> Data? {
        guard let name = job.thumbnailFilename else { return nil }
        return package.thumbnailData(named: name)
    }

    public func imageData(for job: GenerationJob) -> Data? {
        guard let name = job.imageFilename else { return nil }
        return package.imageData(named: name)
    }
}
