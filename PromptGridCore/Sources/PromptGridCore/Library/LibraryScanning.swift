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
                // `contentsOfDirectory` returns directory-package URLs with a
                // trailing slash and a resolved `/private` prefix. Rebuild the URL
                // from `directoryURL` so it's byte-identical to the ones the library
                // API constructs (createProject / renameProject) — the URL is the
                // selection identity, and a mismatch silently drops the selection.
                let canonical = directoryURL.appendingPathComponent(url.lastPathComponent, isDirectory: false)
                return ProjectListItem(
                    url: canonical,
                    displayName: canonical.deletingPathExtension().lastPathComponent,
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

/// Watches a directory two ways: a kernel file-system event source (immediate
/// local changes) and an `NSFilePresenter` (coordinated changes from other
/// processes / iCloud sync). All mutable state is confined to `queue`, so the
/// type is safely `@unchecked Sendable`.
public final class DirectoryLibraryScanner: LibraryScanning, @unchecked Sendable {
    private let directoryURL: URL
    private let queue = DispatchQueue(label: "com.euphoria-ai.PromptGrid.library-scanner")
    private var source: DispatchSourceFileSystemObject?
    private var presenter: LibraryFilePresenter?

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func start(onChange: @escaping @Sendable () -> Void) {
        queue.async { [weak self] in
            guard let self, self.source == nil else { return }
            let fd = open(self.directoryURL.path, O_EVTONLY)
            if fd >= 0 {
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

            let presenter = LibraryFilePresenter(url: self.directoryURL, onChange: onChange)
            NSFileCoordinator.addFilePresenter(presenter)
            self.presenter = presenter
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.source?.cancel()
            self?.source = nil
            if let presenter = self?.presenter {
                NSFileCoordinator.removeFilePresenter(presenter)
                self?.presenter = nil
            }
        }
    }
}

/// Bridges `NSFilePresenter` change callbacks (coordinated / iCloud writes) into
/// a plain change signal.
final class LibraryFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.presentedItemURL = url
        self.onChange = onChange
        super.init()
    }

    func presentedItemDidChange() { onChange() }
    func presentedSubitemDidChange(at url: URL) { onChange() }
}
