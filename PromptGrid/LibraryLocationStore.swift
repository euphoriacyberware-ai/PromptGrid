//
//  LibraryLocationStore.swift
//  PromptGrid
//
//  Persists the user's chosen library folder as a security-scoped bookmark
//  (device-local). Default is the app's private sandbox container; the user may
//  point the library at any folder — an external drive, a NAS, or an iCloud
//  Drive / Dropbox folder to opt into syncing. Nothing leaves the machine unless
//  the user explicitly picks a synced location.
//

import Foundation
import PromptGridCore

enum LibraryLocationStore {
    private static let bookmarkKey = "libraryFolderBookmark"
    private static var defaults: UserDefaults { .standard }

#if os(macOS)
    private static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    private static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
#else
    private static let creationOptions: URL.BookmarkCreationOptions = []
    private static let resolutionOptions: URL.BookmarkResolutionOptions = []
#endif

    /// Whether the library currently lives at a user-chosen location.
    static var hasCustomLocation: Bool { defaults.data(forKey: bookmarkKey) != nil }

    /// Resolve the active library folder, starting security-scoped access for a
    /// custom location so it stays readable/writable for the session. Falls back
    /// to the default local folder if no bookmark or it can't be resolved.
    static func resolveLibraryURL() -> URL {
        guard let data = defaults.data(forKey: bookmarkKey) else {
            return ProjectLibrary.defaultLibraryURL()
        }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: data, options: resolutionOptions,
                              relativeTo: nil, bookmarkDataIsStale: &isStale)
            _ = url.startAccessingSecurityScopedResource() // held for the app session
            if isStale, let refreshed = try? url.bookmarkData(options: creationOptions,
                                                              includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(refreshed, forKey: bookmarkKey)
            }
            return url
        } catch {
            return ProjectLibrary.defaultLibraryURL()
        }
    }

    /// Persist a user-picked folder as the library location. The caller must
    /// already hold security-scoped access to `url` (from the file importer).
    static func setCustomLocation(_ url: URL) throws {
        let data = try url.bookmarkData(options: creationOptions,
                                        includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey)
    }

    /// Return to the default local library location.
    static func useDefault() {
        defaults.removeObject(forKey: bookmarkKey)
    }
}
