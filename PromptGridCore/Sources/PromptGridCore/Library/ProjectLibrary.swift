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

    public let libraryURL: URL
    private let scanner: LibraryScanning
    private var isStarted = false

    public init(libraryURL: URL = ProjectLibrary.defaultLibraryURL(),
                scanner: LibraryScanning? = nil) {
        self.libraryURL = libraryURL
        self.scanner = scanner ?? DirectoryLibraryScanner(directoryURL: libraryURL)
    }

    /// Default local library location. Phase 11 replaces this with the app's
    /// iCloud container's Documents folder.
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

    /// Re-read the folder and publish the result.
    public func refresh() {
        items = LibraryEnumerator.scan(directoryURL: libraryURL)
    }

    // MARK: CRUD

    /// Create a new, empty project and return its sidebar entry.
    @discardableResult
    public func createProject(named rawName: String) throws -> ProjectListItem {
        let name = Self.sanitizedName(rawName)
        let url = uniquePackageURL(forName: name)
        let project = Project(name: url.deletingPathExtension().lastPathComponent)
        let wrapper = try ProjectPackage(project: project).fileWrapper()
        try coordinatedWrite(wrapper, to: url)
        refresh()
        return ProjectListItem(
            url: url,
            displayName: url.deletingPathExtension().lastPathComponent,
            modifiedAt: Date()
        )
    }

    public func deleteProject(_ item: ProjectListItem) throws {
        try coordinatedDelete(item.url)
        refresh()
    }

    /// Read a project's manifest. (Phase 4 uses this to populate the grid.)
    public func loadProject(_ item: ProjectListItem) throws -> Project {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var thrown: Error?
        var project: Project?
        coordinator.coordinate(readingItemAt: item.url, options: [], error: &coordinationError) { url in
            do {
                let wrapper = try FileWrapper(url: url, options: .immediate)
                project = try ProjectPackage(readingFrom: wrapper).project
            } catch {
                thrown = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
        guard let project else { throw LibraryError.couldNotReadProject }
        return project
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

    private func coordinatedWrite(_ wrapper: FileWrapper, to url: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var thrown: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do { try wrapper.write(to: url, options: .atomic, originalContentsURL: nil) }
            catch { thrown = error }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
    }

    private func coordinatedDelete(_ url: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var thrown: Error?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { url in
            do { try FileManager.default.removeItem(at: url) }
            catch { thrown = error }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
    }
}
