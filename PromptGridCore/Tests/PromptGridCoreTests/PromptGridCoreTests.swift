import Testing
@testable import PromptGridCore

@Suite("PromptGridCore skeleton")
struct PromptGridCoreTests {
    @Test("Package exposes the project file extension")
    func projectFileExtension() {
        #expect(PromptGridCore.projectFileExtension == "pgproj")
    }

    @Test("Draw Things dependency types are reachable through the package")
    func dependenciesAreReExported() {
        // Compiles only if DrawThingsClient / DrawThingsQueue are re-exported.
        var config = DrawThingsConfiguration()
        config.seed = 42
        #expect(config.seed == 42)

        let request = GenerationRequest(prompt: "a cat", name: "test")
        #expect(request.prompt == "a cat")
    }
}
