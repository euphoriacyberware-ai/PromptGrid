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

    @Test("Renaming moves the package and updates the manifest name")
    func renameProject() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        let item = try library.createProject(named: "Draft")
        let renamed = try library.renameProject(at: item.url, to: "Final Cut")

        #expect(renamed.displayName == "Final Cut")
        #expect(renamed.url.deletingPathExtension().lastPathComponent == "Final Cut")
        #expect(!FileManager.default.fileExists(atPath: item.url.path))   // old file gone
        #expect(FileManager.default.fileExists(atPath: renamed.url.path))
        #expect(library.items.map(\.displayName) == ["Final Cut"])
        #expect(try library.loadProject(renamed).name == "Final Cut")     // manifest patched
        // The returned URL must be identical to the one the scanner lists, or the
        // sidebar can't reselect the renamed project (URL is the selection id).
        #expect(library.items.first?.id == renamed.id)
    }

    @Test("Listed URLs match the ones the API returns (selection identity)")
    func urlIdentityIsStable() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        let created = try library.createProject(named: "Identity")
        #expect(library.items.first?.id == created.id)   // create → scan identity
    }

    @Test("Renaming preserves generated image files")
    func renamePreservesImages() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        // Build a project with one completed cell so an image file exists on disk.
        var project = Project(name: "WithImage")
        project.prompts.append(Prompt(text: "p", order: 0))
        let store = ProjectStore(url: root.appendingPathComponent("WithImage.pgproj"),
                                 package: ProjectPackage(project: project))
        let (run, jobs) = store.addRun(seed: 1, seedWasRandom: false)
        _ = run
        store.applyResult(jobID: jobs[0].id, imageData: Data([0xAB]), thumbnailData: Data([0xCD]))
        try store.save()
        library.refresh()

        let renamed = try library.renameProject(at: store.url, to: "Renamed")
        let reopened = try ProjectStore(contentsOf: renamed.url)
        let job = reopened.project.prompts[0].jobs.values.first
        #expect(job != nil)
        #expect(reopened.imageData(for: job!) == Data([0xAB]))
    }

    @Test("Renaming to a colliding name is disambiguated")
    func renameCollision() throws {
        let (library, root) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }

        try library.createProject(named: "Taken")
        let other = try library.createProject(named: "Other")
        let renamed = try library.renameProject(at: other.url, to: "Taken")
        #expect(renamed.displayName == "Taken 2")
        #expect(Set(library.items.map(\.displayName)) == ["Taken", "Taken 2"])
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
