//
//  ProjectImporter.swift
//  PromptGridCore
//
//  The inverse of the prompts-JSON export (§11): decode a prompts `.json` file
//  back into a set of prompt rows so it can seed a new project. Only the prompt
//  templates, negative prompts, and configuration are restored — images and
//  reference files aren't part of the JSON.
//

import Foundation

public enum ProjectImporter {

    public enum ImportError: Error, LocalizedError {
        case invalidFormat

        public var errorDescription: String? {
            switch self {
            case .invalidFormat:
                return "This file isn’t a PromptGrid prompts export."
            }
        }
    }

    public struct Result: Sendable {
        /// The project name recorded in the file (the suggested import name).
        public let name: String
        /// Fresh prompt rows (new ids, contiguous order, no jobs).
        public let prompts: [Prompt]
        /// Seed for the imported project's defaults — the first prompt's settings.
        public let defaultSettings: DrawThingsConfigurationDTO
    }

    public static func decode(from data: Data) throws -> Result {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(ProjectExporter.PromptsDocument.self, from: data) else {
            throw ImportError.invalidFormat
        }

        let prompts = document.prompts
            .sorted { $0.row < $1.row }
            .enumerated()
            .map { index, item in
                Prompt(
                    text: item.prompt,
                    negativePrompt: item.negativePrompt,
                    settings: item.configuration,
                    order: index
                )
            }

        let name = document.project.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(
            name: name.isEmpty ? "Imported Prompts" : name,
            prompts: prompts,
            defaultSettings: prompts.first?.settings ?? DrawThingsConfigurationDTO()
        )
    }
}
