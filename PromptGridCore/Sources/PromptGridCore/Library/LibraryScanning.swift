//
//  LibraryScanning.swift
//  PromptGridCore
//
//  The seam between the library and *how* the project folder is watched.
//  Phase 3 ships a local directory watcher; Phase 11 will add an
//  `NSMetadataQuery`-backed scanner over the iCloud ubiquitous scope that also
//  reports per-item sync status. Both just answer one question — "did the folder
//  change?" — and let `ProjectLibrary` re-enumerate.
//

import Foundation

// MARK: - Enumeration

/// Pure, synchronous listing of the project packages in a folder. Centralized
/// so every code path (initial load, change notifications, manual refresh)
/// produces an identical list.
public enum LibraryEnumerator {
    public static func scan(directoryURL: URL) -> [ProjectListItem] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let items = urls
            .filter { $0.pathExtension == PromptGridCore.projectFileExtension }
            .map { url -> ProjectListItem in
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return ProjectListItem(
                    url: url,
                    displayName: url.deletingPathExtension().lastPathComponent,
                    modifiedAt: mod
                )
            }
        return items.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

// MARK: - Scanning

public protocol LibraryScanning: AnyObject, Sendable {
    /// Begin watching. `onChange` fires (on an unspecified queue) whenever the
    /// folder's contents may have changed.
    func start(onChange: @escaping @Sendable () -> Void)
    func stop()
}

/// Watches a local directory with a kernel file-system event source. All mutable
/// state is confined to `queue`, so the type is safely `@unchecked Sendable`.
public final class DirectoryLibraryScanner: LibraryScanning, @unchecked Sendable {
    private let directoryURL: URL
    private let queue = DispatchQueue(label: "com.euphoria-ai.PromptGrid.library-scanner")
    private var source: DispatchSourceFileSystemObject?

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func start(onChange: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            guard let self, self.source == nil else { return }
            let fd = open(self.directoryURL.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .revoke],
                queue: self.queue
            )
            src.setEventHandler { onChange() }
            src.setCancelHandler { close(fd) }
            self.source = src
            src.resume()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.source?.cancel()
            self?.source = nil
        }
    }
}
