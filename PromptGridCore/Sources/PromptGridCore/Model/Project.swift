//
//  Project.swift
//  PromptGridCore
//
//  The document model (Specification §4). A project is a grid of `prompts`
//  (rows) × `runs` (columns); each cell's history lives in `Prompt.jobs`,
//  keyed by `Run.id`.
//
//  `DrawThingsConfiguration` is stored as `DrawThingsConfigurationDTO` (option B)
//  so these types get straightforward `Codable` synthesis.
//

import Foundation

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    /// Copied into new prompts at creation.
    public var defaultSettings: DrawThingsConfigurationDTO
    /// Ordered — grid rows.
    public var prompts: [Prompt]
    /// Ordered — grid columns.
    public var runs: [Run]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        defaultSettings: DrawThingsConfigurationDTO = DrawThingsConfigurationDTO(),
        prompts: [Prompt] = [],
        runs: [Run] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.defaultSettings = defaultSettings
        self.prompts = prompts
        self.runs = runs
    }
}

public struct Prompt: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Template; may contain `{a|b|c}` wildcard groups (Specification §5).
    public var text: String
    public var negativePrompt: String
    /// Copied from project defaults at creation, then independently editable.
    public var settings: DrawThingsConfigurationDTO
    /// Optional img2img/inpaint source stored under `References/`.
    public var referenceImageFilename: String?
    public var order: Int
    /// One entry per cell that has ever been attempted, keyed by `Run.id`.
    public var jobs: [UUID: GenerationJob]

    public init(
        id: UUID = UUID(),
        text: String = "",
        negativePrompt: String = "",
        settings: DrawThingsConfigurationDTO = DrawThingsConfigurationDTO(),
        referenceImageFilename: String? = nil,
        order: Int,
        jobs: [UUID: GenerationJob] = [:]
    ) {
        self.id = id
        self.text = text
        self.negativePrompt = negativePrompt
        self.settings = settings
        self.referenceImageFilename = referenceImageFilename
        self.order = order
        self.jobs = jobs
    }
}

public struct Run: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Display order / column number, 1-based for UI.
    public var index: Int
    /// The client always owns the seed — never derived from a gRPC response
    /// (Specification §2.3).
    public var seed: Int
    /// For display only ("random" vs "fixed" badge) — the value itself is what
    /// matters.
    public var seedWasRandom: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        index: Int,
        seed: Int,
        seedWasRandom: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.index = index
        self.seed = seed
        self.seedWasRandom = seedWasRandom
        self.createdAt = createdAt
    }
}
