//
//  GenerationJob.swift
//  PromptGridCore
//
//  A single grid cell's generation record (Specification §4). Everything frozen
//  into a job at generation time — settings snapshot, resolved prompt/negative
//  prompt, seed — is a historical record and must never be retroactively
//  rewritten. Retrying a failed job re-sends the *same* frozen values.
//

import Foundation

public enum CellRank: String, Codable, Equatable, Sendable, CaseIterable {
    case candidate
    case shortlisted
    case final
}

public enum JobStatus: Codable, Equatable, Sendable {
    case pending
    case generating
    case completed
    case failed(message: String)
    case cancelled
}

public struct GenerationJob: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var runID: UUID
    public var promptID: UUID
    public var status: JobStatus
    /// The seed actually used — chosen client-side before sending.
    public var seedUsed: Int
    /// Frozen at generation time — never mutated after.
    public var settingsSnapshot: DrawThingsConfigurationDTO
    /// Wildcard-resolved text actually sent.
    public var resolvedPrompt: String
    public var resolvedNegativePrompt: String
    /// `nil` until `status == .completed`.
    public var rank: CellRank?
    /// Relative to `Images/`.
    public var imageFilename: String?
    /// Relative to `Thumbnails/`.
    public var thumbnailFilename: String?
    public var createdAt: Date
    public var completedAt: Date?
    public var retryCount: Int

    public init(
        id: UUID = UUID(),
        runID: UUID,
        promptID: UUID,
        status: JobStatus = .pending,
        seedUsed: Int,
        settingsSnapshot: DrawThingsConfigurationDTO,
        resolvedPrompt: String,
        resolvedNegativePrompt: String,
        rank: CellRank? = nil,
        imageFilename: String? = nil,
        thumbnailFilename: String? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.runID = runID
        self.promptID = promptID
        self.status = status
        self.seedUsed = seedUsed
        self.settingsSnapshot = settingsSnapshot
        self.resolvedPrompt = resolvedPrompt
        self.resolvedNegativePrompt = resolvedNegativePrompt
        self.rank = rank
        self.imageFilename = imageFilename
        self.thumbnailFilename = thumbnailFilename
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.retryCount = retryCount
    }
}
