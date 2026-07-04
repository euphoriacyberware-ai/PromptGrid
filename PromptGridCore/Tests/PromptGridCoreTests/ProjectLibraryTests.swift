import Testing
import Foundation
@testable import PromptGridCore

@MainActor
@Suite("ProjectLibrary create/open/delete")
struct ProjectLibraryTests {

    /// A library rooted at a fresh temp folder, with a no-op scanner so tests
    /// drive refresh() explicitly rather than relying on filesystem events.
    private func makeLibrary() throws -> (ProjectLibrary, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let library = ProjectLibrary(libraryURL: root, scanner: NoopScanner())
        return (library, root)
    }

    @Test("Creating a project writes a package and lists it")
    func createProject() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        let item = try library.createProject(named: "My First Project")
        #expect(item.displayName == "My First Project")
        #expect(FileManager.default.fileExists(atPath: item.url.path))
        #expect(item.url.pathExtension == "pgproj")
        #expect(library.items.map(\.displayName) == ["My First Project"])

        // The manifest is present and readable.
        let project = try library.loadProject(item)
        #expect(project.name == "My First Project")
    }

    @Test("Duplicate names are disambiguated, never overwritten")
    func duplicateNames() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        let a = try library.createProject(named: "Ideas")
        let b = try library.createProject(named: "Ideas")
        #expect(a.url != b.url)
        #expect(Set(library.items.map(\.displayName)) == ["Ideas", "Ideas 2"])
    }

    @Test("Illegal filename characters are sanitized")
    func sanitizesNames() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        let item = try library.createProject(named: "a/b:c")
        #expect(item.displayName == "a-b-c")
        #expect(ProjectLibrary.sanitizedName("   ") == "Untitled")
    }

    @Test("Deleting a project removes the package and delists it")
    func deleteProject() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        let item = try library.createProject(named: "Temp")
        try library.deleteProject(item)
        #expect(!FileManager.default.fileExists(atPath: item.url.path))
        #expect(library.items.isEmpty)
    }

    @Test("Refresh reflects packages created out of band")
    func refreshPicksUpExternalPackages() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        library.refresh()
        #expect(library.items.isEmpty)

        // Write a package directly, bypassing the library API.
        let url = root.appendingPathComponent("External.pgproj")
        let wrapper = try ProjectPackage(project: Project(name: "External")).fileWrapper()
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)

        library.refresh()
        #expect(library.items.map(\.displayName) == ["External"])
    }

    @Test("Relocating moves projects and rescans the new folder")
    func relocate() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let newRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: newRoot) }

        try library.createProject(named: "Alpha")
        try library.createProject(named: "Beta")
        #expect(library.items.count == 2)

        let moved = try library.moveProjects(to: newRoot)
        #expect(moved == 2)
        library.relocate(to: newRoot)

        #expect(library.libraryURL == newRoot)
        #expect(Set(library.items.map(\.displayName)) == ["Alpha", "Beta"])
        #expect(LibraryEnumerator.scan(directoryURL: root).isEmpty)
        #expect(FileManager.default.fileExists(atPath: newRoot.appendingPathComponent("Alpha.pgproj").path))
    }
}

/// A scanner that never fires — tests call `refresh()` deterministically.
private final class NoopScanner: LibraryScanning, @unchecked Sendable {
    func start(onChange: @escaping @Sendable () -> Void) {}
    func stop() {}
}
