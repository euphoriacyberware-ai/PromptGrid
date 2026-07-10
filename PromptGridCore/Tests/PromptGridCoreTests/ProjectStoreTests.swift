import Testing
import Foundation
@testable import PromptGridCore

@MainActor
@Suite("ProjectStore editing")
struct ProjectStoreTests {

    private func makeStore(_ project: Project = Project(name: "Grid")) -> ProjectStore {
        ProjectStore(url: URL(fileURLWithPath: "/dev/null"), package: ProjectPackage(project: project))
    }

    @Test("Adding prompts appends with contiguous, zero-based order")
    func addPrompt() {
        let store = makeStore()
        let a = store.addPrompt()
        let b = store.addPrompt()
        #expect(store.project.prompts.count == 2)
        #expect(store.project.prompts[0].id == a.id)
        #expect(store.project.prompts[1].id == b.id)
        #expect(store.project.prompts.map(\.order) == [0, 1])
    }

    @Test("New prompts inherit the project's default settings")
    func addPromptInheritsDefaults() {
        var defaults = DrawThingsConfigurationDTO()
        defaults.steps = 42
        let store = makeStore(Project(name: "Grid", defaultSettings: defaults))
        let prompt = store.addPrompt()
        #expect(prompt.settings.steps == 42)
    }

    @Test("setDefaultSettings updates the project default, seeding future prompts")
    func setDefaultSettings() {
        let store = makeStore()
        var defaults = DrawThingsConfigurationDTO()
        defaults.model = "custom.ckpt"
        store.setDefaultSettings(defaults)
        #expect(store.project.defaultSettings.model == "custom.ckpt")
        #expect(store.addPrompt().settings.model == "custom.ckpt")
    }

    @Test("Removing a prompt renumbers the remaining order")
    func removePromptRenumbers() {
        let store = makeStore()
        let a = store.addPrompt()
        let b = store.addPrompt()
        let c = store.addPrompt()
        store.removePrompt(id: b.id)
        #expect(store.project.prompts.map(\.id) == [a.id, c.id])
        #expect(store.project.prompts.map(\.order) == [0, 1])
    }

    @Test("Moving prompts reorders and renumbers")
    func movePrompts() {
        let store = makeStore()
        let a = store.addPrompt()
        let b = store.addPrompt()
        let c = store.addPrompt()
        // Move the last row to the front.
        store.movePrompts(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(store.project.prompts.map(\.id) == [c.id, a.id, b.id])
        #expect(store.project.prompts.map(\.order) == [0, 1, 2])
    }

    @Test("Inserting a prompt before/after a row places it and renumbers")
    func insertPrompt() {
        let store = makeStore()
        let a = store.addPrompt()
        let b = store.addPrompt()

        // Insert before b -> [a, new, b].
        let mid = store.insertPrompt(relativeTo: b.id, after: false)
        #expect(store.project.prompts.map(\.id) == [a.id, mid.id, b.id])
        #expect(store.project.prompts.map(\.order) == [0, 1, 2])

        // Insert after a -> [a, new2, mid, b].
        let after = store.insertPrompt(relativeTo: a.id, after: true)
        #expect(store.project.prompts.map(\.id) == [a.id, after.id, mid.id, b.id])
        #expect(store.project.prompts.map(\.order) == [0, 1, 2, 3])

        // Unknown id falls back to appending.
        let appended = store.insertPrompt(relativeTo: UUID(), after: false)
        #expect(store.project.prompts.last?.id == appended.id)
    }

    @Test("Applying the project default overwrites prompt settings but not job snapshots")
    func applyDefaultToAllPrompts() {
        var dto = DrawThingsConfigurationDTO()
        dto.steps = 42
        var project = Project(name: "P", defaultSettings: dto)
        project.prompts = [Prompt(text: "a", order: 0), Prompt(settings: { var d = DrawThingsConfigurationDTO(); d.steps = 7; return d }(), order: 1)]
        let store = makeStore(project)
        // A job on prompt 0 snapshots its (pre-apply) settings.
        store.addRun(seed: 1, seedWasRandom: false)
        let snapshotBefore = store.project.prompts[0].jobs.values.first?.settingsSnapshot.steps

        store.applyDefaultSettingsToAllPrompts()
        // Every prompt's editable settings now match the default.
        #expect(store.project.prompts.allSatisfy { $0.settings.steps == 42 })
        // The historical job snapshot is untouched.
        #expect(store.project.prompts[0].jobs.values.first?.settingsSnapshot.steps == snapshotBefore)
    }

    @Test("Removing a prompt deletes its cell images from the package")
    func removePromptDeletesImages() {
        let run = UUID()
        let promptID = UUID()
        let job = GenerationJob(
            runID: run, promptID: promptID, status: .completed,
            seedUsed: 1, settingsSnapshot: DrawThingsConfigurationDTO(),
            resolvedPrompt: "x", resolvedNegativePrompt: "",
            imageFilename: "job.png", thumbnailFilename: "job.png"
        )
        let prompt = Prompt(id: promptID, order: 0, jobs: [run: job])
        let package = ProjectPackage(project: Project(name: "Grid", prompts: [prompt]))
        package.setImageData(Data([1]), named: "job.png")
        package.setThumbnailData(Data([2]), named: "job.png")
        let store = ProjectStore(url: URL(fileURLWithPath: "/dev/null"), package: package)

        store.removePrompt(id: promptID)
        #expect(package.imageData(named: "job.png") == nil)
        #expect(package.thumbnailData(named: "job.png") == nil)
    }

    @Test("Save then reopen round-trips the edited project")
    func savePersists() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Grid.pgproj")

        // Create an on-disk package, open it, edit, save.
        try ProjectPackage(project: Project(name: "Grid")).fileWrapper()
            .write(to: url, options: .atomic, originalContentsURL: nil)
        let store = try ProjectStore(contentsOf: url)
        store.addPrompt()
        store.addPrompt()
        try store.save()

        let reopened = try ProjectStore(contentsOf: url)
        #expect(reopened.project.prompts.count == 2)
    }
}
