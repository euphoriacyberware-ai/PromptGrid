import Testing
import Foundation
@testable import PromptGridCore

@MainActor
@Suite("Export")
struct ExportTests {

    /// A store with `prompts` rows × `runs` cols, all completed, with the given
    /// ranks assigned to prompt 0's cells.
    private func makeStore() -> ProjectStore {
        var project = Project(name: "My Project")
        project.prompts = [
            Prompt(text: "Mountain lake at sunset!", order: 0),
            Prompt(text: "Neon city street", order: 1),
        ]
        let store = ProjectStore(url: URL(fileURLWithPath: "/dev/null"),
                                 package: ProjectPackage(project: project))
        store.addRun(seed: 1, seedWasRandom: false)
        store.addRun(seed: 2, seedWasRandom: false)
        // Complete every cell.
        for prompt in store.project.prompts {
            for run in store.project.runs {
                if let job = prompt.jobs[run.id] {
                    store.applyResult(jobID: job.id, imageData: Data([1]), thumbnailData: Data([2]))
                }
            }
        }
        return store
    }

    private func job(_ store: ProjectStore, prompt: Int, run: Int) -> GenerationJob {
        let p = store.project.prompts[prompt]
        let r = store.project.runs[run]
        return p.jobs[r.id]!
    }

    @Test("Filter counts reflect ranks")
    func filterCounts() {
        let store = makeStore()
        // 2 prompts × 2 runs = 4 completed cells.
        #expect(ProjectExporter.count(in: store.project, filter: .all) == 4)
        #expect(ProjectExporter.count(in: store.project, filter: .finalOnly) == 0)

        store.setRank(jobID: job(store, prompt: 0, run: 0).id, to: .final)
        store.setRank(jobID: job(store, prompt: 1, run: 1).id, to: .shortlisted)
        #expect(ProjectExporter.count(in: store.project, filter: .finalOnly) == 1)
        #expect(ProjectExporter.count(in: store.project, filter: .finalAndShortlisted) == 2)
        #expect(ProjectExporter.count(in: store.project, filter: .all) == 4)
    }

    @Test("Slugify matches the spec examples")
    func slugify() {
        #expect(ProjectExporter.slugify("Mountain lake at sunset") == "mountain-lake-at-sunset")
        #expect(ProjectExporter.slugify("Neon city street!!!") == "neon-city-street")
        #expect(ProjectExporter.slugify("   ") == "untitled")
    }

    @Test("Filenames follow the scheme, with rank suffix and collision handling")
    func filenames() {
        let store = makeStore()
        store.setRank(jobID: job(store, prompt: 0, run: 0).id, to: .final)
        var used = Set<String>()
        let slug = ProjectExporter.slugify(store.project.name)
        let entries = ProjectExporter.entries(in: store.project, filter: .all)
        let names = entries.map { ProjectExporter.uniqueFilename(for: $0, projectSlug: slug, existing: &used) }

        // Filenames carry the project name after the row number.
        // Prompt 0 run 1 -> final; prompt 0 run 2 -> candidate (no suffix).
        #expect(names.contains("01_my-project_mountain-lake-at-sunset_run1_final.png"))
        #expect(names.contains("01_my-project_mountain-lake-at-sunset_run2.png"))
        #expect(names.contains("02_my-project_neon-city-street_run1.png"))
        #expect(Set(names).count == names.count) // all unique
    }

    @Test("A prompt title replaces the prompt-text slug in filenames")
    func filenamesUseTitle() {
        let store = makeStore()
        store.updatePrompt(id: store.project.prompts[0].id) { $0.title = "Hero Shot" }
        var used = Set<String>()
        let slug = ProjectExporter.slugify(store.project.name)
        let names = ProjectExporter.entries(in: store.project, filter: .all)
            .map { ProjectExporter.uniqueFilename(for: $0, projectSlug: slug, existing: &used) }
        // Row 1 uses the title; row 2 (no title) still uses the prompt text.
        #expect(names.contains("01_my-project_hero-shot_run1.png"))
        #expect(names.contains("02_my-project_neon-city-street_run1.png"))
    }

    @Test("Duplicate base names get -2, -3 suffixes")
    func collisions() {
        var used = Set<String>()
        var project = Project(name: "P")
        project.prompts = [Prompt(text: "same", order: 0)]
        let store = ProjectStore(url: URL(fileURLWithPath: "/dev/null"),
                                 package: ProjectPackage(project: project))
        // Two runs, same prompt/rank -> same base name.
        store.addRun(seed: 1, seedWasRandom: false)
        // Force identical run index collision by constructing entries manually.
        let job1 = GenerationJob(runID: UUID(), promptID: store.project.prompts[0].id, status: .completed,
                                 seedUsed: 1, settingsSnapshot: DrawThingsConfigurationDTO(),
                                 resolvedPrompt: "same", resolvedNegativePrompt: "", imageFilename: "a.png")
        let run = store.project.runs[0]
        let e1 = ProjectExporter.Entry(prompt: store.project.prompts[0], run: run, job: job1)
        let n1 = ProjectExporter.uniqueFilename(for: e1, projectSlug: "p", existing: &used)
        let n2 = ProjectExporter.uniqueFilename(for: e1, projectSlug: "p", existing: &used)
        #expect(n1 == "01_p_same_run1.png")
        #expect(n2 == "01_p_same_run1-2.png")
    }

    @Test("Prompts JSON export: All includes ungenerated rows; rank filters gate on images")
    func promptsExport() throws {
        let store = makeStore()
        // Add a third prompt with no images at all.
        let empty = store.addPrompt()
        store.updatePrompt(id: empty.id) { $0.text = "Ungenerated idea" }

        // All → every prompt, even the one that never generated an image.
        #expect(ProjectExporter.promptCount(in: store.project, filter: .all) == 3)
        // Only prompt 0 gets a final image → rank filter keeps just it.
        store.setRank(jobID: job(store, prompt: 0, run: 0).id, to: .final)
        #expect(ProjectExporter.promptCount(in: store.project, filter: .finalOnly) == 1)

        // "All" JSON carries the ungenerated row's template.
        let allData = try ProjectExporter.promptsJSON(project: store.project, filter: .all,
                                                      exportedAt: Date(timeIntervalSince1970: 0))
        let allJSON = String(data: allData, encoding: .utf8)!
        #expect(allJSON.contains("\"project\" : \"My Project\""))
        #expect(allJSON.contains("Ungenerated idea"))

        // "Final only" JSON drops the rows without a final image.
        let finalData = try ProjectExporter.promptsJSON(project: store.project, filter: .finalOnly,
                                                        exportedAt: Date(timeIntervalSince1970: 0))
        let finalJSON = String(data: finalData, encoding: .utf8)!
        #expect(finalJSON.contains("Mountain lake at sunset!"))   // prompt 0 template
        #expect(!finalJSON.contains("Neon city street"))          // filtered out
        #expect(!finalJSON.contains("Ungenerated idea"))          // no image → excluded

        let object = try JSONSerialization.jsonObject(with: finalData) as! [String: Any]
        #expect((object["prompts"] as! [Any]).count == 1)
    }

    @Test("Import decodes an exported prompts JSON back into fresh prompt rows")
    func importRoundTrip() throws {
        let store = makeStore()
        store.updatePrompt(id: store.project.prompts[0].id) {
            $0.title = "Hero Shot"
            $0.notes = "Golden hour, wide angle"
        }
        let data = try ProjectExporter.promptsJSON(project: store.project, filter: .all,
                                                   exportedAt: Date(timeIntervalSince1970: 0))
        // Title + notes are present in the JSON output.
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"title\" : \"Hero Shot\""))
        #expect(json.contains("Golden hour, wide angle"))

        let imported = try ProjectImporter.decode(from: data)
        #expect(imported.name == "My Project")
        #expect(imported.prompts.map(\.text) == ["Mountain lake at sunset!", "Neon city street"])
        #expect(imported.prompts.map(\.order) == [0, 1])
        #expect(imported.prompts.allSatisfy { $0.jobs.isEmpty })   // prompts only, no images
        // Title + notes round-trip back onto the prompt.
        #expect(imported.prompts[0].title == "Hero Shot")
        #expect(imported.prompts[0].notes == "Golden hour, wide angle")
        #expect(imported.prompts[1].title == nil)                  // unset stays nil
    }

    @Test("Import rejects a file that isn't a prompts export")
    func importInvalid() {
        #expect(throws: ProjectImporter.ImportError.self) {
            _ = try ProjectImporter.decode(from: Data(#"{"foo":1}"#.utf8))
        }
    }

    @Test("Export writes a flat folder of PNGs with embedded XMP metadata")
    func exportWritesFilesWithMetadata() throws {
        let store = makeStore()
        store.setRank(jobID: job(store, prompt: 0, run: 0).id, to: .final)

        let png = redPNG()
        let units = ProjectExporter.plan(
            project: store.project, filter: .all, creatorTool: "PromptGrid"
        ) { _ in png }
        #expect(units.count == 4)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let written = try ProjectExporter.write(units, to: dir)
        #expect(written == 4)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.count == 4)
        #expect(files.allSatisfy { $0.hasSuffix(".png") })

        // Verify XMP round-trips out of a written file.
        let finalFile = files.first { $0.contains("_final") }!
        let data = try Data(contentsOf: dir.appendingPathComponent(finalFile))
        #expect(PNGMetadataWriter.readValue(prefix: "xmp", tag: "CreatorTool", from: data) == "PromptGrid")
        let userComment = PNGMetadataWriter.readValue(prefix: "exif", tag: "UserComment", from: data)
        #expect(userComment?.contains("\"rank\":\"final\"") == true)
        #expect(userComment?.contains("\"project\":\"My Project\"") == true)
    }

    @Test("Settings line is human-readable with a display sampler name")
    func settingsLine() {
        var dto = DrawThingsConfigurationDTO()
        dto.steps = 30
        dto.sampler = 0 // dpmpp2mkarras
        dto.guidanceScale = 7.5
        dto.width = 1024; dto.height = 1024
        dto.model = "sd_xl_base_1.0"
        let line = ExportMetadata.settingsLine(dto, seed: 482913)
        #expect(line.contains("Steps: 30"))
        #expect(line.contains("Sampler: DPM++ 2M Karras"))
        #expect(line.contains("Guidance Scale: 7.5"))
        #expect(line.contains("Seed: 482913"))
        #expect(line.contains("Size: 1024x1024"))
    }

    /// A minimal valid PNG (2×2) produced by ImageIO so metadata can attach.
    private func redPNG() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP8z8Dwn4EIwDiqEAAyPQMHhyEmDAAAAABJRU5ErkJggg==")!
    }
}
