//
//  DrawThingsConfigurationDTO.swift
//  PromptGridCore
//
//  A Codable mirror of `DrawThingsConfiguration` (and its nested `LoRAConfig` /
//  `ControlConfig`), which are `Sendable`-only in the dependency. This is the
//  "option B" persistence approach: PromptGrid owns its on-disk schema instead
//  of retroactively conforming a branch-pinned third-party type to `Codable`.
//
//  Design notes:
//  - FlatBuffers enums (`SamplerType`, `CompressionMethod`, `LoRAMode`,
//    `ControlMode`) are stored as their raw `Int8` value, so a future upstream
//    enum case round-trips through JSON even if this build doesn't recognize it.
//  - Decoding is deliberately tolerant: any key missing from an older file falls
//    back to the dependency's own default (`DrawThingsConfiguration()`), so
//    adding a field here never breaks existing project packages. Encoding writes
//    every field (synthesized).
//  - The DTO's own defaults are *derived* from `DrawThingsConfiguration()` rather
//    than hardcoded, so they can't drift from the dependency.
//

import Foundation
import DrawThingsClient

// MARK: - Flexible enum decoding

/// Decode an `Int8` enum raw value that may appear as a JSON number, a numeric
/// string, or a **case-name string** — Draw Things exports some enums as names
/// (e.g. a LoRA `"mode":"all"`), so a config pasted straight from Draw Things
/// must decode. We still *encode* the canonical `Int8`, so saved files are
/// unaffected.
enum FlexibleEnum {
    static func int8<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K,
        names describe: (Int8) -> String?,
        range: ClosedRange<Int8>,
        default fallback: Int8
    ) -> Int8 {
        if let value = try? container.decode(Int8.self, forKey: key) { return value }
        if let string = try? container.decode(String.self, forKey: key) {
            let target = string.lowercased()
            for raw in range where describe(raw)?.lowercased() == target { return raw }
            if let numeric = Int8(string) { return numeric }
        }
        return fallback
    }
}

private func loraModeName(_ raw: Int8) -> String? {
    LoRAMode(rawValue: raw).map { String(describing: $0) }
}

private func controlModeName(_ raw: Int8) -> String? {
    ControlMode(rawValue: raw).map { String(describing: $0) }
}

private func samplerName(_ raw: Int8) -> String? {
    SamplerType(rawValue: raw).map { String(describing: $0) }
}

private func compressionName(_ raw: Int8) -> String? {
    CompressionMethod(rawValue: raw).map { String(describing: $0) }
}

// MARK: - Nested configs

public struct LoRAConfigDTO: Codable, Sendable, Equatable, Hashable {
    public var file: String
    public var weight: Float
    /// Raw value of `LoRAMode`.
    public var mode: Int8

    public init(file: String, weight: Float, mode: Int8) {
        self.file = file
        self.weight = weight
        self.mode = mode
    }

    public init(_ lora: LoRAConfig) {
        self.file = lora.file
        self.weight = lora.weight
        self.mode = lora.mode.rawValue
    }

    public var loraConfig: LoRAConfig {
        LoRAConfig(file: file, weight: weight, mode: LoRAMode(rawValue: mode) ?? .all)
    }

    private enum CodingKeys: String, CodingKey { case file, weight, mode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
        weight = try c.decodeIfPresent(Float.self, forKey: .weight) ?? 1.0
        mode = FlexibleEnum.int8(
            c, forKey: .mode, names: loraModeName,
            range: LoRAMode.min.rawValue...LoRAMode.max.rawValue,
            default: LoRAMode.all.rawValue
        )
    }
}

public struct ControlConfigDTO: Codable, Sendable, Equatable, Hashable {
    public var file: String
    public var weight: Float
    public var guidanceStart: Float
    public var guidanceEnd: Float
    /// Raw value of `ControlMode`.
    public var controlMode: Int8

    public init(file: String, weight: Float, guidanceStart: Float, guidanceEnd: Float, controlMode: Int8) {
        self.file = file
        self.weight = weight
        self.guidanceStart = guidanceStart
        self.guidanceEnd = guidanceEnd
        self.controlMode = controlMode
    }

    public init(_ control: ControlConfig) {
        self.file = control.file
        self.weight = control.weight
        self.guidanceStart = control.guidanceStart
        self.guidanceEnd = control.guidanceEnd
        self.controlMode = control.controlMode.rawValue
    }

    public var controlConfig: ControlConfig {
        ControlConfig(
            file: file,
            weight: weight,
            guidanceStart: guidanceStart,
            guidanceEnd: guidanceEnd,
            controlMode: ControlMode(rawValue: controlMode) ?? .balanced
        )
    }

    private enum CodingKeys: String, CodingKey {
        case file, weight, guidanceStart, guidanceEnd, controlMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
        weight = try c.decodeIfPresent(Float.self, forKey: .weight) ?? 1.0
        guidanceStart = try c.decodeIfPresent(Float.self, forKey: .guidanceStart) ?? 0.0
        guidanceEnd = try c.decodeIfPresent(Float.self, forKey: .guidanceEnd) ?? 1.0
        controlMode = FlexibleEnum.int8(
            c, forKey: .controlMode, names: controlModeName,
            range: ControlMode.min.rawValue...ControlMode.max.rawValue,
            default: ControlMode.balanced.rawValue
        )
    }
}

// MARK: - Configuration

public struct DrawThingsConfigurationDTO: Codable, Sendable, Equatable {
    // Core
    public var width: Int32
    public var height: Int32
    public var steps: Int32
    public var model: String
    /// Raw value of `SamplerType`.
    public var sampler: Int8
    public var guidanceScale: Float
    public var seed: Int64?
    public var clipSkip: Int32
    public var loras: [LoRAConfigDTO]
    public var controls: [ControlConfigDTO]
    public var shift: Float

    // Batch
    public var batchCount: Int32
    public var batchSize: Int32
    public var strength: Float

    // Guidance
    public var imageGuidanceScale: Float
    public var clipWeight: Float
    public var guidanceEmbed: Float
    public var speedUpWithGuidanceEmbed: Bool
    public var cfgZeroStar: Bool
    public var cfgZeroInitSteps: Int32

    // Compression
    /// Raw value of `CompressionMethod`.
    public var compressionArtifacts: Int8
    public var compressionArtifactsQuality: Float

    // Mask / Inpaint
    public var maskBlur: Float
    public var maskBlurOutset: Int32
    public var preserveOriginalAfterInpaint: Bool
    public var enableInpainting: Bool

    // Quality
    public var sharpness: Float
    public var stochasticSamplingGamma: Float
    public var aestheticScore: Float
    public var negativeAestheticScore: Float

    // Image prior
    public var negativePromptForImagePrior: Bool
    public var imagePriorSteps: Int32

    // Crop / Size
    public var cropTop: Int32
    public var cropLeft: Int32
    public var originalImageHeight: Int32
    public var originalImageWidth: Int32
    public var targetImageHeight: Int32
    public var targetImageWidth: Int32
    public var negativeOriginalImageHeight: Int32
    public var negativeOriginalImageWidth: Int32

    // Upscaler
    public var upscalerScaleFactor: Int32

    // Text encoder
    public var resolutionDependentShift: Bool
    public var t5TextEncoder: Bool
    public var separateClipL: Bool
    public var separateOpenClipG: Bool
    public var separateT5: Bool

    // Tiled
    public var tiledDiffusion: Bool
    public var diffusionTileWidth: Int32
    public var diffusionTileHeight: Int32
    public var diffusionTileOverlap: Int32
    public var tiledDecoding: Bool
    public var decodingTileWidth: Int32
    public var decodingTileHeight: Int32
    public var decodingTileOverlap: Int32

    // HiRes Fix
    public var hiresFix: Bool
    public var hiresFixWidth: Int32
    public var hiresFixHeight: Int32
    public var hiresFixStrength: Float

    // Stage 2
    public var stage2Steps: Int32
    public var stage2Guidance: Float
    public var stage2Shift: Float

    // TEA Cache
    public var teaCache: Bool
    public var teaCacheStart: Int32
    public var teaCacheEnd: Int32
    public var teaCacheThreshold: Float
    public var teaCacheMaxSkipSteps: Int32

    // Causal inference
    public var causalInferenceEnabled: Bool
    public var causalInference: Int32
    public var causalInferencePad: Int32

    // Video
    public var fps: Int32
    public var motionScale: Int32
    public var guidingFrameNoise: Float
    public var startFrameGuidance: Float
    public var numFrames: Int32

    // Refiner
    public var refinerModel: String?
    public var refinerStart: Float
    public var zeroNegativePrompt: Bool

    // Misc string fields
    public var upscaler: String?
    public var faceRestoration: String?
    public var name: String?
    public var clipLText: String?
    public var openClipGText: String?
    public var t5Text: String?

    // Seed mode (a plain Int32 in the dependency, not the SeedMode enum)
    public var seedMode: Int32

    // MARK: Bridging

    /// Build a DTO from a live configuration. With no argument, mirrors the
    /// dependency's default configuration.
    public init(_ c: DrawThingsConfiguration = DrawThingsConfiguration()) {
        width = c.width
        height = c.height
        steps = c.steps
        model = c.model
        sampler = c.sampler.rawValue
        guidanceScale = c.guidanceScale
        seed = c.seed
        clipSkip = c.clipSkip
        loras = c.loras.map(LoRAConfigDTO.init)
        controls = c.controls.map(ControlConfigDTO.init)
        shift = c.shift
        batchCount = c.batchCount
        batchSize = c.batchSize
        strength = c.strength
        imageGuidanceScale = c.imageGuidanceScale
        clipWeight = c.clipWeight
        guidanceEmbed = c.guidanceEmbed
        speedUpWithGuidanceEmbed = c.speedUpWithGuidanceEmbed
        cfgZeroStar = c.cfgZeroStar
        cfgZeroInitSteps = c.cfgZeroInitSteps
        compressionArtifacts = c.compressionArtifacts.rawValue
        compressionArtifactsQuality = c.compressionArtifactsQuality
        maskBlur = c.maskBlur
        maskBlurOutset = c.maskBlurOutset
        preserveOriginalAfterInpaint = c.preserveOriginalAfterInpaint
        enableInpainting = c.enableInpainting
        sharpness = c.sharpness
        stochasticSamplingGamma = c.stochasticSamplingGamma
        aestheticScore = c.aestheticScore
        negativeAestheticScore = c.negativeAestheticScore
        negativePromptForImagePrior = c.negativePromptForImagePrior
        imagePriorSteps = c.imagePriorSteps
        cropTop = c.cropTop
        cropLeft = c.cropLeft
        originalImageHeight = c.originalImageHeight
        originalImageWidth = c.originalImageWidth
        targetImageHeight = c.targetImageHeight
        targetImageWidth = c.targetImageWidth
        negativeOriginalImageHeight = c.negativeOriginalImageHeight
        negativeOriginalImageWidth = c.negativeOriginalImageWidth
        upscalerScaleFactor = c.upscalerScaleFactor
        resolutionDependentShift = c.resolutionDependentShift
        t5TextEncoder = c.t5TextEncoder
        separateClipL = c.separateClipL
        separateOpenClipG = c.separateOpenClipG
        separateT5 = c.separateT5
        tiledDiffusion = c.tiledDiffusion
        diffusionTileWidth = c.diffusionTileWidth
        diffusionTileHeight = c.diffusionTileHeight
        diffusionTileOverlap = c.diffusionTileOverlap
        tiledDecoding = c.tiledDecoding
        decodingTileWidth = c.decodingTileWidth
        decodingTileHeight = c.decodingTileHeight
        decodingTileOverlap = c.decodingTileOverlap
        hiresFix = c.hiresFix
        hiresFixWidth = c.hiresFixWidth
        hiresFixHeight = c.hiresFixHeight
        hiresFixStrength = c.hiresFixStrength
        stage2Steps = c.stage2Steps
        stage2Guidance = c.stage2Guidance
        stage2Shift = c.stage2Shift
        teaCache = c.teaCache
        teaCacheStart = c.teaCacheStart
        teaCacheEnd = c.teaCacheEnd
        teaCacheThreshold = c.teaCacheThreshold
        teaCacheMaxSkipSteps = c.teaCacheMaxSkipSteps
        causalInferenceEnabled = c.causalInferenceEnabled
        causalInference = c.causalInference
        causalInferencePad = c.causalInferencePad
        fps = c.fps
        motionScale = c.motionScale
        guidingFrameNoise = c.guidingFrameNoise
        startFrameGuidance = c.startFrameGuidance
        numFrames = c.numFrames
        refinerModel = c.refinerModel
        refinerStart = c.refinerStart
        zeroNegativePrompt = c.zeroNegativePrompt
        upscaler = c.upscaler
        faceRestoration = c.faceRestoration
        name = c.name
        clipLText = c.clipLText
        openClipGText = c.openClipGText
        t5Text = c.t5Text
        seedMode = c.seedMode
    }

    /// Reconstruct a live configuration. Unknown enum raw values fall back to a
    /// sane default rather than failing.
    ///
    /// Optional model-path fields (`refinerModel`, `upscaler`, `faceRestoration`)
    /// are normalized empty-string → `nil`: Draw Things exports a disabled model
    /// as `""`, but on the wire a present-but-empty string is treated as "enabled
    /// with the server default" — which invokes e.g. face restoration with an
    /// incompatible model and crashes the server. Sending `nil` (absent) is what
    /// actually means "disabled".
    public var configuration: DrawThingsConfiguration {
        func nilIfEmpty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return DrawThingsConfiguration(
            width: width,
            height: height,
            steps: steps,
            model: model,
            sampler: SamplerType(rawValue: sampler) ?? .dpmpp2mkarras,
            guidanceScale: guidanceScale,
            seed: seed,
            clipSkip: clipSkip,
            loras: loras.map(\.loraConfig),
            controls: controls.map(\.controlConfig),
            shift: shift,
            batchCount: batchCount,
            batchSize: batchSize,
            strength: strength,
            imageGuidanceScale: imageGuidanceScale,
            clipWeight: clipWeight,
            guidanceEmbed: guidanceEmbed,
            speedUpWithGuidanceEmbed: speedUpWithGuidanceEmbed,
            cfgZeroStar: cfgZeroStar,
            cfgZeroInitSteps: cfgZeroInitSteps,
            compressionArtifacts: CompressionMethod(rawValue: compressionArtifacts) ?? .disabled,
            compressionArtifactsQuality: compressionArtifactsQuality,
            maskBlur: maskBlur,
            maskBlurOutset: maskBlurOutset,
            preserveOriginalAfterInpaint: preserveOriginalAfterInpaint,
            enableInpainting: enableInpainting,
            sharpness: sharpness,
            stochasticSamplingGamma: stochasticSamplingGamma,
            aestheticScore: aestheticScore,
            negativeAestheticScore: negativeAestheticScore,
            negativePromptForImagePrior: negativePromptForImagePrior,
            imagePriorSteps: imagePriorSteps,
            cropTop: cropTop,
            cropLeft: cropLeft,
            originalImageHeight: originalImageHeight,
            originalImageWidth: originalImageWidth,
            targetImageHeight: targetImageHeight,
            targetImageWidth: targetImageWidth,
            negativeOriginalImageHeight: negativeOriginalImageHeight,
            negativeOriginalImageWidth: negativeOriginalImageWidth,
            upscalerScaleFactor: upscalerScaleFactor,
            resolutionDependentShift: resolutionDependentShift,
            t5TextEncoder: t5TextEncoder,
            separateClipL: separateClipL,
            separateOpenClipG: separateOpenClipG,
            separateT5: separateT5,
            tiledDiffusion: tiledDiffusion,
            diffusionTileWidth: diffusionTileWidth,
            diffusionTileHeight: diffusionTileHeight,
            diffusionTileOverlap: diffusionTileOverlap,
            tiledDecoding: tiledDecoding,
            decodingTileWidth: decodingTileWidth,
            decodingTileHeight: decodingTileHeight,
            decodingTileOverlap: decodingTileOverlap,
            hiresFix: hiresFix,
            hiresFixWidth: hiresFixWidth,
            hiresFixHeight: hiresFixHeight,
            hiresFixStrength: hiresFixStrength,
            stage2Steps: stage2Steps,
            stage2Guidance: stage2Guidance,
            stage2Shift: stage2Shift,
            teaCache: teaCache,
            teaCacheStart: teaCacheStart,
            teaCacheEnd: teaCacheEnd,
            teaCacheThreshold: teaCacheThreshold,
            teaCacheMaxSkipSteps: teaCacheMaxSkipSteps,
            causalInferenceEnabled: causalInferenceEnabled,
            causalInference: causalInference,
            causalInferencePad: causalInferencePad,
            fps: fps,
            motionScale: motionScale,
            guidingFrameNoise: guidingFrameNoise,
            startFrameGuidance: startFrameGuidance,
            numFrames: numFrames,
            refinerModel: nilIfEmpty(refinerModel),
            refinerStart: refinerStart,
            zeroNegativePrompt: zeroNegativePrompt,
            upscaler: nilIfEmpty(upscaler),
            faceRestoration: nilIfEmpty(faceRestoration),
            name: name,
            clipLText: clipLText,
            openClipGText: openClipGText,
            t5Text: t5Text,
            seedMode: seedMode
        )
    }

    // MARK: Tolerant decoding

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DrawThingsConfiguration() // dependency defaults for any missing key

        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }

        width = try v(.width, d.width)
        height = try v(.height, d.height)
        steps = try v(.steps, d.steps)
        model = try v(.model, d.model)
        sampler = FlexibleEnum.int8(
            c, forKey: .sampler, names: samplerName,
            range: SamplerType.min.rawValue...SamplerType.max.rawValue,
            default: d.sampler.rawValue
        )
        guidanceScale = try v(.guidanceScale, d.guidanceScale)
        // `seed` is optional in the model; treat a present explicit null as nil.
        seed = try c.decodeIfPresent(Int64.self, forKey: .seed) ?? d.seed
        clipSkip = try v(.clipSkip, d.clipSkip)
        loras = try v(.loras, [])
        controls = try v(.controls, [])
        shift = try v(.shift, d.shift)
        batchCount = try v(.batchCount, d.batchCount)
        batchSize = try v(.batchSize, d.batchSize)
        strength = try v(.strength, d.strength)
        imageGuidanceScale = try v(.imageGuidanceScale, d.imageGuidanceScale)
        clipWeight = try v(.clipWeight, d.clipWeight)
        guidanceEmbed = try v(.guidanceEmbed, d.guidanceEmbed)
        speedUpWithGuidanceEmbed = try v(.speedUpWithGuidanceEmbed, d.speedUpWithGuidanceEmbed)
        cfgZeroStar = try v(.cfgZeroStar, d.cfgZeroStar)
        cfgZeroInitSteps = try v(.cfgZeroInitSteps, d.cfgZeroInitSteps)
        compressionArtifacts = FlexibleEnum.int8(
            c, forKey: .compressionArtifacts, names: compressionName,
            range: CompressionMethod.min.rawValue...CompressionMethod.max.rawValue,
            default: d.compressionArtifacts.rawValue
        )
        compressionArtifactsQuality = try v(.compressionArtifactsQuality, d.compressionArtifactsQuality)
        maskBlur = try v(.maskBlur, d.maskBlur)
        maskBlurOutset = try v(.maskBlurOutset, d.maskBlurOutset)
        preserveOriginalAfterInpaint = try v(.preserveOriginalAfterInpaint, d.preserveOriginalAfterInpaint)
        enableInpainting = try v(.enableInpainting, d.enableInpainting)
        sharpness = try v(.sharpness, d.sharpness)
        stochasticSamplingGamma = try v(.stochasticSamplingGamma, d.stochasticSamplingGamma)
        aestheticScore = try v(.aestheticScore, d.aestheticScore)
        negativeAestheticScore = try v(.negativeAestheticScore, d.negativeAestheticScore)
        negativePromptForImagePrior = try v(.negativePromptForImagePrior, d.negativePromptForImagePrior)
        imagePriorSteps = try v(.imagePriorSteps, d.imagePriorSteps)
        cropTop = try v(.cropTop, d.cropTop)
        cropLeft = try v(.cropLeft, d.cropLeft)
        originalImageHeight = try v(.originalImageHeight, d.originalImageHeight)
        originalImageWidth = try v(.originalImageWidth, d.originalImageWidth)
        targetImageHeight = try v(.targetImageHeight, d.targetImageHeight)
        targetImageWidth = try v(.targetImageWidth, d.targetImageWidth)
        negativeOriginalImageHeight = try v(.negativeOriginalImageHeight, d.negativeOriginalImageHeight)
        negativeOriginalImageWidth = try v(.negativeOriginalImageWidth, d.negativeOriginalImageWidth)
        upscalerScaleFactor = try v(.upscalerScaleFactor, d.upscalerScaleFactor)
        resolutionDependentShift = try v(.resolutionDependentShift, d.resolutionDependentShift)
        t5TextEncoder = try v(.t5TextEncoder, d.t5TextEncoder)
        separateClipL = try v(.separateClipL, d.separateClipL)
        separateOpenClipG = try v(.separateOpenClipG, d.separateOpenClipG)
        separateT5 = try v(.separateT5, d.separateT5)
        tiledDiffusion = try v(.tiledDiffusion, d.tiledDiffusion)
        diffusionTileWidth = try v(.diffusionTileWidth, d.diffusionTileWidth)
        diffusionTileHeight = try v(.diffusionTileHeight, d.diffusionTileHeight)
        diffusionTileOverlap = try v(.diffusionTileOverlap, d.diffusionTileOverlap)
        tiledDecoding = try v(.tiledDecoding, d.tiledDecoding)
        decodingTileWidth = try v(.decodingTileWidth, d.decodingTileWidth)
        decodingTileHeight = try v(.decodingTileHeight, d.decodingTileHeight)
        decodingTileOverlap = try v(.decodingTileOverlap, d.decodingTileOverlap)
        hiresFix = try v(.hiresFix, d.hiresFix)
        hiresFixWidth = try v(.hiresFixWidth, d.hiresFixWidth)
        hiresFixHeight = try v(.hiresFixHeight, d.hiresFixHeight)
        hiresFixStrength = try v(.hiresFixStrength, d.hiresFixStrength)
        stage2Steps = try v(.stage2Steps, d.stage2Steps)
        stage2Guidance = try v(.stage2Guidance, d.stage2Guidance)
        stage2Shift = try v(.stage2Shift, d.stage2Shift)
        teaCache = try v(.teaCache, d.teaCache)
        teaCacheStart = try v(.teaCacheStart, d.teaCacheStart)
        teaCacheEnd = try v(.teaCacheEnd, d.teaCacheEnd)
        teaCacheThreshold = try v(.teaCacheThreshold, d.teaCacheThreshold)
        teaCacheMaxSkipSteps = try v(.teaCacheMaxSkipSteps, d.teaCacheMaxSkipSteps)
        causalInferenceEnabled = try v(.causalInferenceEnabled, d.causalInferenceEnabled)
        causalInference = try v(.causalInference, d.causalInference)
        causalInferencePad = try v(.causalInferencePad, d.causalInferencePad)
        fps = try v(.fps, d.fps)
        motionScale = try v(.motionScale, d.motionScale)
        guidingFrameNoise = try v(.guidingFrameNoise, d.guidingFrameNoise)
        startFrameGuidance = try v(.startFrameGuidance, d.startFrameGuidance)
        numFrames = try v(.numFrames, d.numFrames)
        refinerModel = try c.decodeIfPresent(String.self, forKey: .refinerModel) ?? d.refinerModel
        refinerStart = try v(.refinerStart, d.refinerStart)
        zeroNegativePrompt = try v(.zeroNegativePrompt, d.zeroNegativePrompt)
        upscaler = try c.decodeIfPresent(String.self, forKey: .upscaler) ?? d.upscaler
        faceRestoration = try c.decodeIfPresent(String.self, forKey: .faceRestoration) ?? d.faceRestoration
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        clipLText = try c.decodeIfPresent(String.self, forKey: .clipLText) ?? d.clipLText
        openClipGText = try c.decodeIfPresent(String.self, forKey: .openClipGText) ?? d.openClipGText
        t5Text = try c.decodeIfPresent(String.self, forKey: .t5Text) ?? d.t5Text
        seedMode = try v(.seedMode, d.seedMode)
    }
}
