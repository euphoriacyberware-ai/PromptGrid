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

    /// Apply an edit to a prompt's non-frozen fields (text, negative prompt,
    /// settings). Existing jobs are historical records and are never touched (§4).
    public func updatePrompt(id: UUID, _ transform: (inout Prompt) -> Void) {
        guard let index = project.prompts.firstIndex(where: { $0.id == id }) else { return }
        transform(&project.prompts[index])
    }

    /// Set a prompt's reference image (img2img/inpaint source), writing it into
    /// `References/` keyed by the prompt id.
    public func setReferenceImage(promptID: UUID, data: Data) {
        guard let index = project.prompts.firstIndex(where: { $0.id == promptID }) else { return }
        let name = "\(promptID).png"
        package.setReferenceData(data, named: name)
        project.prompts[index].referenceImageFilename = name
    }

    public func clearReferenceImage(promptID: UUID) {
        guard let index = project.prompts.firstIndex(where: { $0.id == promptID }) else { return }
        if let name = project.prompts[index].referenceImageFilename {
            package.removeReference(named: name)
        }
        project.prompts[index].referenceImageFilename = nil
    }

    // MARK: Run (column) mutations

    /// Create a run and, for every existing prompt, a frozen `pending` job
    /// (Specification §7). Wildcards are resolved *now* and frozen; the settings
    /// snapshot and seed are frozen too (§4, §5). Returns the run plus the jobs
    /// that a caller should enqueue — the actual queue submission is wired up in
    /// Phase 6.
    @discardableResult
    public func addRun(seed: Int, seedWasRandom: Bool, generateJobs: Bool = true) -> (run: Run, jobs: [GenerationJob]) {
        let run = Run(index: project.runs.count + 1, seed: seed, seedWasRandom: seedWasRandom)
        project.runs.append(run)

        // When `generateJobs` is false the run's cells start empty — the user
        // fills them later (single-cell Generate, or Generate Missing).
        guard generateJobs else { return (run, []) }

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

    /// Create a job for a single empty cell (a prompt added after the run
    /// existed, §7). Freezes the resolved prompts, settings, and the run's seed
    /// now, exactly like `addRun`. Returns the job to enqueue, or `nil` if the
    /// cell already has one.
    @discardableResult
    public func generateCell(promptID: UUID, runID: UUID) -> GenerationJob? {
        guard let promptIndex = project.prompts.firstIndex(where: { $0.id == promptID }),
              let run = project.runs.first(where: { $0.id == runID }),
              project.prompts[promptIndex].jobs[runID] == nil
        else { return nil }

        let prompt = project.prompts[promptIndex]
        let job = GenerationJob(
            runID: runID,
            promptID: promptID,
            status: .pending,
            seedUsed: run.seed,
            settingsSnapshot: prompt.settings,
            resolvedPrompt: WildcardResolver.resolve(prompt.text),
            resolvedNegativePrompt: WildcardResolver.resolve(prompt.negativePrompt)
        )
        project.prompts[promptIndex].jobs[runID] = job
        return job
    }

    /// Number of cells (prompt × run) with no job yet — the "missing" images.
    public func missingCellCount() -> Int {
        var count = 0
        for prompt in project.prompts {
            for run in project.runs where prompt.jobs[run.id] == nil {
                count += 1
            }
        }
        return count
    }

    /// Create a frozen pending job for every empty cell and return them to
    /// enqueue — the batch "fill in everything missing" action. Cells that
    /// already have a job (completed/failed/etc.) are left untouched; delete one
    /// first to regenerate it. Wildcards re-roll and current settings/seed are
    /// snapshotted per cell, exactly like single-cell generate.
    @discardableResult
    public func generateMissing(order: GenerationOrder = .bySeed) -> [GenerationJob] {
        var created: [GenerationJob] = []
        func fill(_ promptID: UUID, _ runID: UUID) {
            if let job = generateCell(promptID: promptID, runID: runID) { created.append(job) }
        }
        switch order {
        case .bySeed:   // run (column) outer, prompt inner
            for run in project.runs {
                for prompt in project.prompts { fill(prompt.id, run.id) }
            }
        case .byPrompt: // prompt (row) outer, run inner
            for prompt in project.prompts {
                for run in project.runs { fill(prompt.id, run.id) }
            }
        }
        return created
    }

    // MARK: Ranking (Specification §10)

    /// The single coordinating method for ranks. Setting `.final` first demotes
    /// any other `.final` job **in the same prompt** to `.shortlisted`, so at most
    /// one job per prompt (across all its runs) is ever `.final`. No other code
    /// path sets `.final` directly.
    public func setRank(jobID: UUID, to rank: CellRank?) {
        guard let promptIndex = project.prompts.firstIndex(where: {
            $0.jobs.values.contains { $0.id == jobID }
        }) else { return }

        if rank == .final {
            for (runID, job) in project.prompts[promptIndex].jobs
            where job.id != jobID && job.rank == .final {
                var demoted = job
                demoted.rank = .shortlisted
                project.prompts[promptIndex].jobs[runID] = demoted
            }
        }

        if let entry = project.prompts[promptIndex].jobs.first(where: { $0.value.id == jobID }) {
            var job = entry.value
            job.rank = rank
            project.prompts[promptIndex].jobs[entry.key] = job
        }
    }

    /// Delete a single cell's job and its image files, reverting the cell to
    /// empty (so it can be generated again). Works for any status — the way to
    /// clear a failed generation that the queue can no longer retry.
    public func deleteCell(promptID: UUID, runID: UUID) {
        guard let promptIndex = project.prompts.firstIndex(where: { $0.id == promptID }),
              let job = project.prompts[promptIndex].jobs[runID] else { return }
        if let name = job.imageFilename { package.removeImage(named: name) }
        if let name = job.thumbnailFilename { package.removeThumbnail(named: name) }
        project.prompts[promptIndex].jobs[runID] = nil
    }

    // MARK: Results

    /// Apply a finished generation to its job. Returns `false` — writing nothing —
    /// if the job or its run no longer exists, which is the orphan-result guard
    /// (Specification §7, step 2): a result can arrive after its run was deleted.
    @discardableResult
    public func applyResult(jobID: UUID, imageData: Data, thumbnailData: Data,
                            completedAt: Date = Date()) -> Bool {
        let imageName = "\(jobID).png"
        let applied = updateJob(jobID) { job in
            job.status = .completed
            job.rank = .candidate
            job.imageFilename = imageName
            job.thumbnailFilename = imageName
            job.completedAt = completedAt
        }
        if applied {
            package.setImageData(imageData, named: imageName)
            package.setThumbnailData(thumbnailData, named: imageName)
        }
        return applied
    }

    /// Mark a job as in-flight when the queue starts it.
    @discardableResult
    public func markGenerating(jobID: UUID) -> Bool {
        updateJob(jobID) { $0.status = .generating }
    }

    /// Record a generation failure (the message is shown in the cell/inspector).
    @discardableResult
    public func markFailed(jobID: UUID, message: String) -> Bool {
        updateJob(jobID) { $0.status = .failed(message: message) }
    }

    /// Record that a job was cancelled in the queue.
    @discardableResult
    public func markCancelled(jobID: UUID) -> Bool {
        updateJob(jobID) { $0.status = .cancelled }
    }

    /// Find a job by id, apply `transform`, and write it back — unless the job or
    /// its run no longer exists (the orphan guard, §7 step 2), in which case it
    /// returns `false` and changes nothing.
    @discardableResult
    private func updateJob(_ jobID: UUID, _ transform: (inout GenerationJob) -> Void) -> Bool {
        guard let promptIndex = project.prompts.firstIndex(where: {
            $0.jobs.values.contains { $0.id == jobID }
        }), var job = project.prompts[promptIndex].jobs.values.first(where: { $0.id == jobID }),
              project.runs.contains(where: { $0.id == job.runID })
        else { return false }

        transform(&job)
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

    /// A prompt's optional img2img/inpaint reference source, from `References/`.
    public func referenceImageData(for prompt: Prompt) -> Data? {
        guard let name = prompt.referenceImageFilename else { return nil }
        return package.referenceData(named: name)
    }
}
