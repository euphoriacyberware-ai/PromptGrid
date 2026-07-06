//
//  ProjectLibrary.swift
//  PromptGridCore
//
//  The observable model behind the sidebar (Specification §2.2, §3). Owns the
//  library folder, keeps `items` in sync with its real contents by scanning
//  (no index database), and performs create/open/delete. Writes and deletes go
//  through `NSFileCoordinator`; full `NSFilePresenter` correctness and the
//  iCloud container land in Phase 11.
//

import Foundation
import Observation

@MainActor
@Observable
public final class ProjectLibrary {

    public enum LibraryError: Swift.Error, Equatable {
        case couldNotReadProject
    }

    /// The current sidebar contents, sorted by display name.
    public private(set) var items: [ProjectListItem] = []
    /// Surfaced to the UI when a filesystem operation fails.
    public var lastError: String?

    public private(set) var libraryURL: URL
    private var scanner: LibraryScanning
    private var isStarted = false

    public init(libraryURL: URL = ProjectLibrary.defaultLibraryURL(),
                scanner: LibraryScanning? = nil) {
        self.libraryURL = libraryURL
        self.scanner = scanner ?? DirectoryLibraryScanner(directoryURL: libraryURL)
    }

    /// Default local library location — the app's private sandbox container.
    /// Deliberately *not* under `~/Documents` so it isn't swept into iCloud by
    /// "Desktop & Documents" sync. The user can opt into another location.
    nonisolated public static func defaultLibraryURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false)) ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.euphoria-ai.PromptGrid"
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Projects", isDirectory: true)
    }

    // MARK: Lifecycle

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        do {
            try FileManager.default.createDirectory(
                at: libraryURL, withIntermediateDirectories: true)
        } catch {
            lastError = error.localizedDescription
        }
        scanner.start { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    public func stop() {
        scanner.stop()
        isStarted = false
    }

    /// Point the library at a different folder and rescan. Files are *not* moved
    /// — the caller relocates any existing projects first.
    public func relocate(to newURL: URL) {
        let wasStarted = isStarted
        if isStarted { scanner.stop(); isStarted = false }
        libraryURL = newURL
        scanner = DirectoryLibraryScanner(directoryURL: newURL)
        if wasStarted { start() } else { refresh() }
    }

    /// Move every project package from the current library folder into `newURL`,
    /// returning the number moved. Used before `relocate` when the user changes
    /// the library location and wants to bring existing projects along.
    @discardableResult
    public func moveProjects(to newURL: URL) throws -> Int {
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        var moved = 0
        for item in LibraryEnumerator.scan(directoryURL: libraryURL) {
            let destination = newURL.appendingPathComponent(item.url.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try FileManager.default.moveItem(at: item.url, to: destination)
            moved += 1
        }
        return moved
    }

    /// Re-read the folder and publish the result.
    public func refresh() {
        items = LibraryEnumerator.scan(directoryURL: libraryURL)
    }

    // MARK: CRUD

    /// Create a new, empty project and return its sidebar entry. `defaultSettings`
    /// (the app-level generation defaults) seed the project's own defaults, which
    /// in turn seed each new prompt.
    @discardableResult
    public func createProject(named rawName: String,
                              defaultSettings: DrawThingsConfigurationDTO = DrawThingsConfigurationDTO()) throws -> ProjectListItem {
        let name = Self.sanitizedName(rawName)
        let url = uniquePackageURL(forName: name)
        let project = Project(name: url.deletingPathExtension().lastPathComponent,
                              defaultSettings: defaultSettings)
        let wrapper = try ProjectPackage(project: project).fileWrapper()
        try FileCoordination.write(wrapper, to: url)
        refresh()
        return ProjectListItem(
            url: url,
            displayName: url.deletingPathExtension().lastPathComponent,
            modifiedAt: Date()
        )
    }

    /// Rename a project: move its `.pgproj` to a new basename (the display name is
    /// the filename) and patch the manifest's stored name to match. Only
    /// `Manifest.json` is rewritten — image files are left untouched. Returns the
    /// renamed sidebar entry (with its new URL). A no-op basename change just
    /// re-syncs the manifest name.
    @discardableResult
    public func renameProject(at oldURL: URL, to rawName: String) throws -> ProjectListItem {
        let newName = Self.sanitizedName(rawName)
        let currentBase = oldURL.deletingPathExtension().lastPathComponent
        let destURL = (newName == currentBase) ? oldURL : uniquePackageURL(forName: newName)
        if destURL != oldURL {
            try FileCoordination.move(from: oldURL, to: destURL)
        }

        let finalBase = destURL.deletingPathExtension().lastPathComponent
        var project = try FileCoordination.read(at: destURL) { url in
            try ProjectPackage(readingFrom: FileWrapper(url: url, options: .immediate)).project
        }
        if project.name != finalBase {
            project.name = finalBase
            let data = try ProjectPackage.makeEncoder().encode(project)
            let manifestURL = destURL.appendingPathComponent(ProjectPackage.manifestFilename)
            try FileCoordination.writeData(data, to: manifestURL)
        }

        refresh()
        let mod = (try? destURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return ProjectListItem(url: destURL, displayName: finalBase, modifiedAt: mod)
    }

    public func deleteProject(_ item: ProjectListItem) throws {
        try FileCoordination.delete(at: item.url)
        refresh()
    }

    /// Read a project's manifest.
    public func loadProject(_ item: ProjectListItem) throws -> Project {
        try FileCoordination.read(at: item.url) { url in
            let wrapper = try FileWrapper(url: url, options: .immediate)
            return try ProjectPackage(readingFrom: wrapper).project
        }
    }

    // MARK: Helpers

    /// Strip characters that are illegal in a filename and collapse whitespace.
    static func sanitizedName(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    /// `Name.pgproj`, disambiguated as `Name 2.pgproj`, `Name 3.pgproj`, … on
    /// collision so an existing project is never overwritten.
    private func uniquePackageURL(forName name: String) -> URL {
        let ext = PromptGridCore.projectFileExtension
        var candidate = libraryURL.appendingPathComponent(name).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = libraryURL
                .appendingPathComponent("\(name) \(counter)")
                .appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }
}
