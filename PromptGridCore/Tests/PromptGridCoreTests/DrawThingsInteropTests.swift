import Testing
import Foundation
@testable import PromptGridCore
import DrawThingsClient

@Suite("Draw Things config interop")
struct DrawThingsInteropTests {

    /// A configuration copied verbatim from the Draw Things app: note the LoRA
    /// `"mode":"all"` string enums that previously broke decoding.
    private let pastedConfig = #"""
    {"height":1280,"sharpness":0,"strength":1,"upscaler":"","batchCount":1,"batchSize":1,"sampler":17,"hiresFix":false,"shift":3,"maskBlur":1.5,"tiledDecoding":false,"cfgZeroInitSteps":0,"seedMode":2,"loras":[{"mode":"all","file":"sam_v6.1_lora_f16.ckpt","weight":0.80000000000000004},{"mode":"all","file":"mystic_xxx_zit_v7_lora_f16.ckpt","weight":0.59999999999999998}],"preserveOriginalAfterInpaint":true,"causalInferencePad":0,"resolutionDependentShift":false,"refinerModel":"","maskBlurOutset":0,"model":"z_image_turbo_1.0_f16.ckpt","width":1280,"guidanceScale":1,"controls":[],"tiledDiffusion":false,"cfgZeroStar":false,"faceRestoration":"","steps":10,"seed":3879793493}
    """#

    @Test("A config pasted straight from Draw Things decodes")
    func decodesPastedConfig() throws {
        let dto = try ProjectPackage.makeDecoder()
            .decode(DrawThingsConfigurationDTO.self, from: Data(pastedConfig.utf8))

        #expect(dto.width == 1280)
        #expect(dto.height == 1280)
        #expect(dto.steps == 10)
        #expect(dto.sampler == 17)                       // numeric enum, unchanged
        #expect(dto.seed == 3_879_793_493)               // > Int32.max, fits Int64
        #expect(dto.loras.count == 2)
        #expect(dto.loras[0].file == "sam_v6.1_lora_f16.ckpt")
        #expect(dto.loras[0].mode == LoRAMode.all.rawValue)  // "all" string -> 0

        // And it bridges to a live configuration.
        let config = dto.configuration
        #expect(config.loras.first?.mode == .all)
    }

    @Test("String-named LoRA modes map to the right raw values")
    func loraModeStringNames() throws {
        func decodeMode(_ name: String) throws -> Int8 {
            let json = #"{ "file": "x", "weight": 1, "mode": "\#(name)" }"#
            return try ProjectPackage.makeDecoder()
                .decode(LoRAConfigDTO.self, from: Data(json.utf8)).mode
        }
        #expect(try decodeMode("all") == LoRAMode.all.rawValue)
        #expect(try decodeMode("base") == LoRAMode.base.rawValue)
        #expect(try decodeMode("refiner") == LoRAMode.refiner.rawValue)
        // Numeric string still works.
        #expect(try decodeMode("2") == 2)
    }

    @Test("We still encode enums as the canonical Int8 (files unaffected)")
    func encodesCanonicalInt8() throws {
        let dto = LoRAConfigDTO(LoRAConfig(file: "x", weight: 1, mode: .refiner))
        let data = try ProjectPackage.makeEncoder().encode(dto)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("\"mode\" : 2"))          // number, not "refiner"
    }
}
