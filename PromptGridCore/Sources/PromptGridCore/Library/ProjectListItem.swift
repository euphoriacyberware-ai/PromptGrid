//
//  ProjectListItem.swift
//  PromptGridCore
//
//  A lightweight sidebar entry for one project package in the library folder
//  (Specification §2.2). Built by scanning the folder — there is no separate
//  index database. The display name is the package's filename stem, so the
//  scan never has to open a manifest.
//

import Foundation

public struct ProjectListItem: Identifiable, Hashable, Sendable {
    /// The `.pgproj` package URL; also the stable identity for selection.
    public let url: URL
    public let displayName: String
    public let modifiedAt: Date?
    public var syncStatus: SyncStatus

    public var id: URL { url }

    /// iCloud state, surfaced by the `NSMetadataQuery` scanner in Phase 11.
    /// Everything is `.local` until then.
    public enum SyncStatus: Sendable, Hashable {
        case local
        case upToDate
        case downloading
        case uploading
    }

    public init(url: URL, displayName: String, modifiedAt: Date?, syncStatus: SyncStatus = .local) {
        self.url = url
        self.displayName = displayName
        self.modifiedAt = modifiedAt
        self.syncStatus = syncStatus
    }
}
