import Testing
import Foundation
@testable import PromptGridCore
import DrawThingsClient

@MainActor
@Suite("Generation request building + settings")
struct GenerationTests {

    @Test("Request is built from the frozen job (id, seed, resolved text)")
    func requestFromJob() {
        var settings = DrawThingsConfigurationDTO()
        settings.steps = 33
        let prompt = Prompt(text: "raw {a|b}", settings: settings, order: 0)
        let run = Run(index: 2, seed: 555, seedWasRandom: false)
        let job = GenerationJob(
            id: UUID(), runID: run.id, promptID: prompt.id,
            seedUsed: 555, settingsSnapshot: settings,
            resolvedPrompt: "raw a", resolvedNegativePrompt: "bad"
        )
        let project = Project(name: "Proj", prompts: [prompt], runs: [run])

        let request = GenerationRequestBuilder.request(for: job, in: project)
        #expect(request.id == job.id)                    // correlation
        #expect(request.prompt == "raw a")               // frozen, not re-resolved
        #expect(request.negativePrompt == "bad")
        #expect(request.configuration.seed == 555)       // run seed always wins
        #expect(request.configuration.steps == 33)
        #expect(request.name == "Proj · Row 1 · Run 2")
    }

    @Test("Retry rebuilds an identical request from the same job")
    func retryIsIdentical() {
        let prompt = Prompt(text: "x", order: 0)
        let run = Run(index: 1, seed: 9, seedWasRandom: true)
        let job = GenerationJob(runID: run.id, promptID: prompt.id, seedUsed: 9,
                                settingsSnapshot: DrawThingsConfigurationDTO(),
                                resolvedPrompt: "frozen", resolvedNegativePrompt: "")
        let project = Project(name: "P", prompts: [prompt], runs: [run])

        let first = GenerationRequestBuilder.request(for: job, in: project)
        let second = GenerationRequestBuilder.request(for: job, in: project)
        #expect(first.id == second.id)
        #expect(first.prompt == second.prompt)
        #expect(first.configuration.seed == second.configuration.seed)
    }

    @Test("Server settings round-trip through an isolated UserDefaults")
    func settingsPersist() throws {
        let suite = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = ServerSettings(host: "192.168.1.10", port: 7859, useTLS: true, sharedSecret: "s3cret")
        settings.save(to: defaults)
        let loaded = ServerSettings.load(from: defaults)
        #expect(loaded == settings)
        #expect(loaded.addressString == "192.168.1.10:7859")
        #expect(loaded.isConfigured)
    }

    @Test("Empty host is not configured")
    func notConfigured() {
        #expect(!ServerSettings().isConfigured)
        #expect(ServerSettings(host: "  ").isConfigured == false)
    }

    // MARK: Job status mutations

    private func storeWithOneJob() -> (ProjectStore, GenerationJob) {
        var project = Project(name: "P")
        project.prompts.append(Prompt(text: "p", order: 0))
        let store = ProjectStore(url: URL(fileURLWithPath: "/dev/null"),
                                 package: ProjectPackage(project: project))
        let (_, jobs) = store.addRun(seed: 1, seedWasRandom: false)
        return (store, jobs[0])
    }

    @Test("markGenerating / markFailed update status behind the orphan guard")
    func statusTransitions() {
        let (store, job) = storeWithOneJob()
        #expect(store.markGenerating(jobID: job.id))
        #expect(currentStatus(store, job.id) == .generating)

        #expect(store.markFailed(jobID: job.id, message: "boom"))
        #expect(currentStatus(store, job.id) == .failed(message: "boom"))
    }

    @Test("Status changes for a deleted run are discarded")
    func statusOrphanGuard() {
        let (store, job) = storeWithOneJob()
        store.deleteRun(id: store.project.runs[0].id)
        #expect(store.markGenerating(jobID: job.id) == false)
        #expect(store.markFailed(jobID: job.id, message: "x") == false)
        #expect(store.markCancelled(jobID: job.id) == false)
    }

    private func currentStatus(_ store: ProjectStore, _ jobID: UUID) -> JobStatus? {
        for prompt in store.project.prompts {
            if let job = prompt.jobs.values.first(where: { $0.id == jobID }) { return job.status }
        }
        return nil
    }
}
