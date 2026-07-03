import Testing
import Foundation
@testable import PromptGridCore

@MainActor
@Suite("Prompt editing")
struct PromptEditingTests {

    private func store(_ project: Project) -> ProjectStore {
        ProjectStore(url: URL(fileURLWithPath: "/dev/null"), package: ProjectPackage(project: project))
    }

    @Test("Editing a prompt's fields doesn't touch its frozen jobs")
    func editDoesNotTouchJobs() {
        var project = Project(name: "P")
        project.prompts.append(Prompt(text: "old", order: 0))
        let s = store(project)
        let (run, jobs) = s.addRun(seed: 1, seedWasRandom: false)
        let frozenPrompt = jobs[0].resolvedPrompt

        s.updatePrompt(id: s.project.prompts[0].id) { p in
            p.text = "new template {a|b}"
            p.negativePrompt = "nope"
            var settings = p.settings
            settings.steps = 50
            p.settings = settings
        }

        #expect(s.project.prompts[0].text == "new template {a|b}")
        #expect(s.project.prompts[0].settings.steps == 50)
        // The already-created job keeps its frozen resolved prompt.
        #expect(s.project.prompts[0].jobs[run.id]?.resolvedPrompt == frozenPrompt)
    }

    @Test("Setting and clearing a reference image writes/removes it in the package")
    func referenceImageLifecycle() {
        var project = Project(name: "P")
        let promptID = UUID()
        project.prompts.append(Prompt(id: promptID, order: 0))
        let package = ProjectPackage(project: project)
        let s = ProjectStore(url: URL(fileURLWithPath: "/dev/null"), package: package)

        s.setReferenceImage(promptID: promptID, data: Data([9, 8, 7]))
        #expect(s.project.prompts[0].referenceImageFilename == "\(promptID).png")
        #expect(package.referenceData(named: "\(promptID).png") == Data([9, 8, 7]))

        s.clearReferenceImage(promptID: promptID)
        #expect(s.project.prompts[0].referenceImageFilename == nil)
        #expect(package.referenceData(named: "\(promptID).png") == nil)
    }

    @Test("JSON config edits round-trip through the DTO decoder")
    func jsonConfigRoundTrip() throws {
        var dto = DrawThingsConfigurationDTO()
        dto.steps = 25
        dto.model = "custom.safetensors"
        let json = try ProjectPackage.makeEncoder().encode(dto)
        let text = String(data: json, encoding: .utf8)!

        // Simulate the editor: decode the edited text back into a DTO.
        let decoded = try ProjectPackage.makeDecoder()
            .decode(DrawThingsConfigurationDTO.self, from: Data(text.utf8))
        #expect(decoded.steps == 25)
        #expect(decoded.model == "custom.safetensors")

        // A type error surfaces as a thrown error (the editor shows it inline).
        let bad = Data(#"{ "steps": "not a number" }"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try ProjectPackage.makeDecoder().decode(DrawThingsConfigurationDTO.self, from: bad)
        }
    }
}
