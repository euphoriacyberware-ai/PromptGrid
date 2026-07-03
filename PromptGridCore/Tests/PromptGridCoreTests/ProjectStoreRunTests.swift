import Testing
import Foundation
@testable import PromptGridCore

@MainActor
@Suite("ProjectStore runs")
struct ProjectStoreRunTests {

    private func makeStore(prompts: Int = 0) -> ProjectStore {
        var project = Project(name: "Grid")
        for i in 0..<prompts {
            project.prompts.append(Prompt(text: "prompt \(i)", order: i))
        }
        return ProjectStore(url: URL(fileURLWithPath: "/dev/null"),
                            package: ProjectPackage(project: project))
    }

    @Test("Adding a run creates a pending, frozen job for every prompt")
    func addRunCreatesJobs() {
        let store = makeStore(prompts: 3)
        let (run, jobs) = store.addRun(seed: 482913, seedWasRandom: false)

        #expect(store.project.runs.map(\.index) == [1])
        #expect(jobs.count == 3)
        for prompt in store.project.prompts {
            let job = prompt.jobs[run.id]
            #expect(job?.status == .pending)
            #expect(job?.seedUsed == 482913)
            #expect(job?.promptID == prompt.id)
        }
    }

    @Test("Wildcards are resolved and frozen at run creation")
    func addRunFreezesResolvedPrompt() {
        var project = Project(name: "Grid")
        project.prompts.append(Prompt(text: "a {cat|cat} on a mat", order: 0))
        let store = ProjectStore(url: URL(fileURLWithPath: "/dev/null"),
                                 package: ProjectPackage(project: project))
        let (run, _) = store.addRun(seed: 1, seedWasRandom: true)
        // Both options are "cat", so resolution is deterministic here.
        #expect(store.project.prompts[0].jobs[run.id]?.resolvedPrompt == "a cat on a mat")
    }

    @Test("Runs added after a prompt has no backfill; new prompt has empty cells")
    func noBackfill() {
        let store = makeStore(prompts: 1)
        let (run, _) = store.addRun(seed: 1, seedWasRandom: false)
        // Add a prompt *after* the run exists.
        let late = store.addPrompt()
        #expect(store.project.prompts.first(where: { $0.id == late.id })?.jobs[run.id] == nil)
    }

    @Test("Second run's index is 2")
    func runIndexing() {
        let store = makeStore(prompts: 1)
        store.addRun(seed: 1, seedWasRandom: false)
        store.addRun(seed: 2, seedWasRandom: true)
        #expect(store.project.runs.map(\.index) == [1, 2])
    }

    @Test("cancellableJobIDs returns only pending/generating jobs")
    func cancellable() {
        let store = makeStore(prompts: 2)
        let (run, jobs) = store.addRun(seed: 1, seedWasRandom: false)
        // Both jobs start pending.
        #expect(Set(store.cancellableJobIDs(forRunID: run.id)) == Set(jobs.map(\.id)))
    }

    @Test("Deleting a run removes its jobs, images, and renumbers remaining runs")
    func deleteRun() {
        let store = makeStore(prompts: 2)
        let (run1, _) = store.addRun(seed: 1, seedWasRandom: false)
        let (run2, _) = store.addRun(seed: 2, seedWasRandom: false)

        store.deleteRun(id: run1.id)
        #expect(store.project.runs.map(\.id) == [run2.id])
        #expect(store.project.runs.map(\.index) == [1])          // renumbered
        for prompt in store.project.prompts {
            #expect(prompt.jobs[run1.id] == nil)                 // jobs gone
            #expect(prompt.jobs[run2.id] != nil)                 // other run intact
        }
    }

    @Test("Completed-image count drives the delete confirmation copy")
    func completedCount() {
        let store = makeStore(prompts: 2)
        let (run, jobs) = store.addRun(seed: 1, seedWasRandom: false)
        #expect(store.completedImageCount(forRunID: run.id) == 0)
        // Complete one job.
        #expect(store.applyResult(jobID: jobs[0].id, imageData: Data([1]), thumbnailData: Data([2])))
        #expect(store.completedImageCount(forRunID: run.id) == 1)
    }

    @Test("applyResult writes image + thumbnail and marks the job completed")
    func applyResultWrites() {
        let store = makeStore(prompts: 1)
        let (_, jobs) = store.addRun(seed: 1, seedWasRandom: false)
        let job = jobs[0]
        #expect(store.applyResult(jobID: job.id, imageData: Data([1, 2]), thumbnailData: Data([3, 4])))

        let updated = store.project.prompts[0].jobs.values.first { $0.id == job.id }
        #expect(updated?.status == .completed)
        #expect(updated?.rank == .candidate)
        #expect(updated?.imageFilename == "\(job.id).png")
        #expect(store.imageData(for: updated!) == Data([1, 2]))
        #expect(store.thumbnailData(for: updated!) == Data([3, 4]))
    }

    @Test("Orphan guard: a result for a deleted run is discarded, writing nothing")
    func orphanResultDiscarded() {
        let store = makeStore(prompts: 1)
        let (run, jobs) = store.addRun(seed: 1, seedWasRandom: false)
        let job = jobs[0]
        store.deleteRun(id: run.id)

        #expect(store.applyResult(jobID: job.id, imageData: Data([1]), thumbnailData: Data([2])) == false)
        // Nothing was written back for the vanished job.
        #expect(store.project.prompts[0].jobs.isEmpty)
    }
}
