//
//  ExportMetadata.swift
//  PromptGridCore
//
//  Builds the XMP payload for an exported image (Specification §11.1): the
//  human-readable `dc:description` settings line and the `exif:UserComment` JSON.
//

import Foundation
import DrawThingsClient

enum ExportMetadata {

    static func payload(for entry: ProjectExporter.Entry, project: Project,
                        creatorTool: String) -> PNGMetadataWriter.Payload {
        let job = entry.job
        let settings = job.settingsSnapshot

        let description = "\(job.resolvedPrompt)\n\(settingsLine(settings, seed: job.seedUsed))"
        let userComment = userCommentJSON(for: entry, project: project)

        return PNGMetadataWriter.Payload(
            creatorTool: creatorTool,
            description: description,
            userComment: userComment
        )
    }

    /// e.g. "Steps: 30, Sampler: DPM++ 2M Karras, Guidance Scale: 7.5, Seed:
    /// 482913, Size: 1024x1024, Model: sd_xl_base_1.0, Strength: 1.0" plus LoRA lines.
    static func settingsLine(_ s: DrawThingsConfigurationDTO, seed: Int) -> String {
        var parts = [
            "Steps: \(s.steps)",
            "Sampler: \(samplerName(s.sampler))",
            "Guidance Scale: \(trimFloat(s.guidanceScale))",
            "Seed: \(seed)",
            "Size: \(s.width)x\(s.height)",
            "Model: \(s.model)",
            "Strength: \(trimFloat(s.strength))",
        ]
        for lora in s.loras {
            parts.append("LoRA: \(lora.file) (\(trimFloat(lora.weight)))")
        }
        return parts.joined(separator: ", ")
    }

    private static func userCommentJSON(for entry: ProjectExporter.Entry, project: Project) -> String {
        let payload = UserComment(
            prompt: entry.job.resolvedPrompt,
            negativePrompt: entry.job.resolvedNegativePrompt,
            seed: entry.job.seedUsed,
            rank: entry.job.rank?.rawValue,
            project: project.name,
            run: entry.run.index,
            generatedAt: entry.job.completedAt,
            configuration: entry.job.settingsSnapshot
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    private struct UserComment: Encodable {
        let prompt: String
        let negativePrompt: String
        let seed: Int
        let rank: String?
        let project: String
        let run: Int
        let generatedAt: Date?
        let configuration: DrawThingsConfigurationDTO
    }

    /// Draw Things' display names for the FlatBuffers sampler enum.
    static func samplerName(_ raw: Int8) -> String {
        switch raw {
        case 0: return "DPM++ 2M Karras"
        case 1: return "Euler a"
        case 2: return "DDIM"
        case 3: return "PLMS"
        case 4: return "DPM++ SDE Karras"
        case 5: return "UniPC"
        case 6: return "LCM"
        case 7: return "Euler A Substep"
        case 8: return "DPM++ SDE Substep"
        case 9: return "TCD"
        case 10: return "Euler A Trailing"
        case 11: return "DPM++ SDE Trailing"
        case 12: return "DPM++ 2M AYS"
        case 13: return "Euler A AYS"
        case 14: return "DPM++ SDE AYS"
        case 15: return "DPM++ 2M Trailing"
        case 16: return "DDIM Trailing"
        case 17: return "UniPC Trailing"
        case 18: return "UniPC AYS"
        case 19: return "TCD Trailing"
        default: return "Sampler \(raw)"
        }
    }

    private static func trimFloat(_ value: Float) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%g", value)
    }
}
