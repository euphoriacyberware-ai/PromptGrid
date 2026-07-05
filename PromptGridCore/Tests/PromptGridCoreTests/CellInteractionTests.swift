import Testing
import Foundation
@testable import PromptGridCore

@MainActor
@Suite("Cell interactions: generate + rank")
struct CellInteractionTests {

    private func storeWithGrid(prompts: Int, seed: Int = 1) -> ProjectStore {
        var project = Project(name: "P")
        for i in 0..<prompts { project.prompts.append(Prompt(text: "p\(i) {a|a}", order: i)) }
        return ProjectStore(url: URL(fileURLWithPath: "/dev/null"),
                            package: ProjectPackage(project: project))
    }

    @Test("Generating an empty cell freezes a pending job with the run's seed")
    func generateEmptyCell() {
        let store = storeWithGrid(prompts: 1)
        let (run, _) = store.addRun(seed: 42, seedWasRandom: false)
        // Add a prompt *after* the run — its cell is empty (no backfill).
        let late = store.addPrompt()

        let job = store.generateCell(promptID: late.id, runID: run.id)
        #expect(job != nil)
        #expect(job?.status == .pending)
        #expect(job?.seedUsed == 42)
        #expect(store.project.prompts.first { $0.id == late.id }?.jobs[run.id]?.id == job?.id)
    }

    @Test("Generating a cell that already has a job returns nil")
    func generateNonEmptyCell() {
        let store = storeWithGrid(prompts: 1)
        let (run, jobs) = store.addRun(seed: 1, seedWasRandom: false)
        let promptID = store.project.prompts[0].id
        #expect(store.generateCell(promptID: promptID, runID: run.id) == nil)
        // Unchanged.
        #expect(store.project.prompts[0].jobs[run.id]?.id == jobs[0].id)
    }

    @Test("Only one job per prompt can be final; setting a new final demotes the old")
    func oneFinalPerRow() {
        let store = storeWithGrid(prompts: 1)
        let (r1, j1) = store.addRun(seed: 1, seedWasRandom: false)
        let (r2, j2) = store.addRun(seed: 2, seedWasRandom: false)
        store.applyResult(jobID: j1[0].id, imageData: Data([1]), thumbnailData: Data([1]))
        store.applyResult(jobID: j2[0].id, imageData: Data([2]), thumbnailData: Data([2]))

        store.setRank(jobID: j1[0].id, to: .final)
        #expect(rank(store, j1[0].id) == .final)

        // Promote the second: the first must be demoted to shortlisted.
        store.setRank(jobID: j2[0].id, to: .final)
        #expect(rank(store, j2[0].id) == .final)
        #expect(rank(store, j1[0].id) == .shortlisted)
        _ = (r1, r2)
    }

    @Test("Finals in different prompts are independent")
    func finalPerPromptIndependent() {
        let store = storeWithGrid(prompts: 2)
        let (_, jobs) = store.addRun(seed: 1, seedWasRandom: false)
        // jobs[0] is prompt 0's cell, jobs[1] is prompt 1's cell.
        store.setRank(jobID: jobs[0].id, to: .final)
        store.setRank(jobID: jobs[1].id, to: .final)
        #expect(rank(store, jobs[0].id) == .final)
        #expect(rank(store, jobs[1].id) == .final)
    }

    @Test("Generate Missing fills only the empty cells")
    func generateMissing() {
        let store = storeWithGrid(prompts: 2)
        let (r1, _) = store.addRun(seed: 1, seedWasRandom: false)  // both prompts get jobs
        store.addRun(seed: 2, seedWasRandom: false)                 // both prompts get jobs
        // Add a prompt after the runs -> 2 empty cells (no backfill).
        let late = store.addPrompt()
        // Delete one existing cell -> 1 more empty.
        store.deleteCell(promptID: store.project.prompts[0].id, runID: r1.id)

        #expect(store.missingCellCount() == 3)   // 2 (late prompt × 2 runs) + 1 deleted
        let created = store.generateMissing()
        #expect(created.count == 3)
        #expect(store.missingCellCount() == 0)   // all filled
        #expect(created.allSatisfy { $0.status == .pending })
        // Existing jobs weren't recreated.
        #expect(store.project.prompts.first { $0.id == late.id }?.jobs.count == 2)
    }

    @Test("Generate Missing order: bySeed is column-major, byPrompt is row-major")
    func generateMissingOrder() {
        func sequence(_ order: GenerationOrder) -> [(p: Int, r: Int)] {
            let store = storeWithGrid(prompts: 2)
            let (r0, _) = store.addRun(seed: 1, seedWasRandom: false, generateJobs: false)
            let (r1, _) = store.addRun(seed: 2, seedWasRandom: false, generateJobs: false)
            let p0 = store.project.prompts[0].id, p1 = store.project.prompts[1].id
            let created = store.generateMissing(order: order)
            return created.map { job in
                (p: job.promptID == p0 ? 0 : 1, r: job.runID == r0.id ? 0 : 1)
            }
        }
        // bySeed: run0 fully (p0,p1), then run1.
        #expect(sequence(.bySeed).map { "\($0.p)\($0.r)" } == ["00", "10", "01", "11"])
        // byPrompt: prompt0 fully (r0,r1), then prompt1.
        #expect(sequence(.byPrompt).map { "\($0.p)\($0.r)" } == ["00", "01", "10", "11"])
    }

    @Test("Deleting a cell removes its job and image, reverting it to empty")
    func deleteCell() {
        let store = storeWithGrid(prompts: 1)
        let (run, jobs) = store.addRun(seed: 1, seedWasRandom: false)
        let promptID = store.project.prompts[0].id
        store.applyResult(jobID: jobs[0].id, imageData: Data([1]), thumbnailData: Data([2]))
        #expect(store.project.prompts[0].jobs[run.id] != nil)

        store.deleteCell(promptID: promptID, runID: run.id)
        #expect(store.project.prompts[0].jobs[run.id] == nil)  // empty again
        // Regeneratable after deletion.
        #expect(store.generateCell(promptID: promptID, runID: run.id) != nil)
    }

    @Test("Delete Row Images clears every cell in a prompt, keeping other rows")
    func deleteRowImages() {
        let store = storeWithGrid(prompts: 2)
        store.addRun(seed: 1, seedWasRandom: false)
        store.addRun(seed: 2, seedWasRandom: false)
        let p0 = store.project.prompts[0].id
        let p1 = store.project.prompts[1].id

        #expect(store.filledCellCount(inRow: p0) == 2)
        store.deleteRowImages(promptID: p0)
        #expect(store.filledCellCount(inRow: p0) == 0)   // row cleared
        #expect(store.filledCellCount(inRow: p1) == 2)   // other row untouched
    }

    @Test("Delete Column Images clears every cell in a run, keeping the column")
    func deleteColumnImages() {
        let store = storeWithGrid(prompts: 2)
        let (r0, _) = store.addRun(seed: 1, seedWasRandom: false)
        let (r1, _) = store.addRun(seed: 2, seedWasRandom: false)

        #expect(store.filledCellCount(inColumn: r0.id) == 2)
        store.deleteColumnImages(runID: r0.id)
        #expect(store.filledCellCount(inColumn: r0.id) == 0)  // column cleared
        #expect(store.filledCellCount(inColumn: r1.id) == 2)  // other column untouched
        // The run (seed column) itself still exists.
        #expect(store.project.runs.contains { $0.id == r0.id })
    }

    private func rank(_ store: ProjectStore, _ jobID: UUID) -> CellRank? {
        for prompt in store.project.prompts {
            if let job = prompt.jobs.values.first(where: { $0.id == jobID }) { return job.rank }
        }
        return nil
    }
}
