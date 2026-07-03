import Testing
import Foundation
@testable import PromptGridCore
import DrawThingsClient

@Suite("Model Codable round-trips")
struct ModelCodableTests {

    // MARK: Configuration DTO

    @Test("Default DTO mirrors the dependency's default configuration")
    func defaultDTOMatchesDependencyDefaults() {
        let dto = DrawThingsConfigurationDTO()
        let defaults = DrawThingsConfiguration()
        #expect(dto.steps == defaults.steps)
        #expect(dto.model == defaults.model)
        #expect(dto.sampler == defaults.sampler.rawValue)
        #expect(dto.guidanceScale == defaults.guidanceScale)
        #expect(dto.seedMode == defaults.seedMode)
    }

    @Test("DTO -> configuration -> DTO is lossless")
    func dtoConfigurationBridgeRoundTrips() {
        var config = DrawThingsConfiguration()
        config.width = 1024
        config.height = 768
        config.steps = 30
        config.model = "custom_model.safetensors"
        config.sampler = .unipc
        config.guidanceScale = 6.5
        config.seed = 482913
        config.compressionArtifacts = .jpeg
        config.loras = [LoRAConfig(file: "style.lora", weight: 0.8, mode: .base)]
        config.controls = [ControlConfig(file: "depth", weight: 0.5, guidanceStart: 0.1, guidanceEnd: 0.9, controlMode: .control)]
        config.refinerModel = "refiner.safetensors"

        let rebuilt = DrawThingsConfigurationDTO(config).configuration
        #expect(rebuilt.width == 1024)
        #expect(rebuilt.height == 768)
        #expect(rebuilt.steps == 30)
        #expect(rebuilt.model == "custom_model.safetensors")
        #expect(rebuilt.sampler == .unipc)
        #expect(rebuilt.guidanceScale == 6.5)
        #expect(rebuilt.seed == 482913)
        #expect(rebuilt.compressionArtifacts == .jpeg)
        #expect(rebuilt.loras.count == 1)
        #expect(rebuilt.loras.first?.file == "style.lora")
        #expect(rebuilt.loras.first?.mode == .base)
        #expect(rebuilt.controls.first?.controlMode == .control)
        #expect(rebuilt.refinerModel == "refiner.safetensors")
    }

    @Test("DTO survives JSON encode/decode")
    func dtoJSONRoundTrips() throws {
        var config = DrawThingsConfiguration()
        config.sampler = .lcm
        config.seed = 7
        config.loras = [LoRAConfig(file: "a.lora", weight: 1.0, mode: .refiner)]
        let dto = DrawThingsConfigurationDTO(config)

        let data = try ProjectPackage.makeEncoder().encode(dto)
        let decoded = try ProjectPackage.makeDecoder().decode(DrawThingsConfigurationDTO.self, from: data)
        #expect(decoded == dto)
    }

    @Test("Missing keys fall back to dependency defaults on decode")
    func tolerantDecodingFillsMissingKeys() throws {
        // Only two keys present; everything else must default rather than throw.
        let json = #"{ "steps": 42, "model": "partial.safetensors" }"#.data(using: .utf8)!
        let decoded = try ProjectPackage.makeDecoder().decode(DrawThingsConfigurationDTO.self, from: json)
        let defaults = DrawThingsConfigurationDTO()
        #expect(decoded.steps == 42)
        #expect(decoded.model == "partial.safetensors")
        #expect(decoded.guidanceScale == defaults.guidanceScale)
        #expect(decoded.sampler == defaults.sampler)
        #expect(decoded.width == defaults.width)
    }

    @Test("Unknown enum raw value degrades to a default rather than crashing")
    func unknownEnumRawValueFallsBack() {
        var dto = DrawThingsConfigurationDTO()
        dto.sampler = 120 // no such SamplerType case
        #expect(dto.configuration.sampler == .dpmpp2mkarras)
        // The raw value is preserved in the DTO for a future build that knows it.
        #expect(dto.sampler == 120)
    }

    // MARK: Project graph

    @Test("A populated project round-trips through JSON")
    func projectRoundTrips() throws {
        // Whole-second dates: manifest timestamps are ISO 8601 second precision.
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let run = Run(index: 1, seed: 482913, seedWasRandom: false, createdAt: date)
        let job = GenerationJob(
            runID: run.id,
            promptID: UUID(),
            status: .failed(message: "server unreachable"),
            seedUsed: 482913,
            settingsSnapshot: DrawThingsConfigurationDTO(),
            resolvedPrompt: "a mountain lake",
            resolvedNegativePrompt: "blurry",
            rank: .final,
            createdAt: date,
            retryCount: 2
        )
        let prompt = Prompt(
            text: "a {mountain|desert} lake",
            negativePrompt: "blurry",
            order: 0,
            jobs: [run.id: job]
        )
        let project = Project(
            name: "Test",
            createdAt: date,
            modifiedAt: date,
            prompts: [prompt],
            runs: [run]
        )

        let data = try ProjectPackage.makeEncoder().encode(project)
        let decoded = try ProjectPackage.makeDecoder().decode(Project.self, from: data)
        #expect(decoded == project)
        #expect(decoded.prompts.first?.jobs[run.id]?.status == .failed(message: "server unreachable"))
        #expect(decoded.prompts.first?.jobs[run.id]?.rank == .final)
    }
}
