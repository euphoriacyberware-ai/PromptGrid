import Testing
import Foundation
@testable import PromptGridCore

@Suite("ProjectPackage read/write round-trip")
struct ProjectPackageTests {

    private func sampleProject() -> Project {
        // Whole-second dates: manifest timestamps are ISO 8601 second precision.
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let run = Run(index: 1, seed: 99, seedWasRandom: true, createdAt: date)
        let prompt = Prompt(text: "a cat", order: 0)
        return Project(name: "Shoebox", createdAt: date, modifiedAt: date, prompts: [prompt], runs: [run])
    }

    @Test("Writing then reading a package preserves the project")
    func manifestRoundTrips() throws {
        let project = sampleProject()
        let package = ProjectPackage(project: project)

        let wrapper = try package.fileWrapper()
        #expect(wrapper.isDirectory)
        #expect(wrapper.fileWrappers?[ProjectPackage.manifestFilename] != nil)
        // The three asset directories are always materialized.
        #expect(wrapper.fileWrappers?[ProjectPackage.imagesDirectory]?.isDirectory == true)
        #expect(wrapper.fileWrappers?[ProjectPackage.thumbnailsDirectory]?.isDirectory == true)
        #expect(wrapper.fileWrappers?[ProjectPackage.referencesDirectory]?.isDirectory == true)

        let reopened = try ProjectPackage(readingFrom: wrapper)
        #expect(reopened.project == project)
    }

    @Test("Image data survives a write/read cycle")
    func imageDataRoundTrips() throws {
        let package = ProjectPackage(project: sampleProject())
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        package.setImageData(pngBytes, named: "job-1.png")
        package.setThumbnailData(pngBytes, named: "job-1.png")
        package.setReferenceData(pngBytes, named: "prompt-1.png")

        let wrapper = try package.fileWrapper()
        let reopened = try ProjectPackage(readingFrom: wrapper)
        #expect(reopened.imageData(named: "job-1.png") == pngBytes)
        #expect(reopened.thumbnailData(named: "job-1.png") == pngBytes)
        #expect(reopened.referenceData(named: "prompt-1.png") == pngBytes)
    }

    @Test("A saved package survives a real filesystem write/read")
    func filesystemRoundTrips() throws {
        let package = ProjectPackage(project: sampleProject())
        package.setImageData(Data([1, 2, 3, 4]), named: "job-1.png")

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Shoebox.pgproj", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        try package.fileWrapper().write(to: dir, options: .atomic, originalContentsURL: nil)

        let readWrapper = try FileWrapper(url: dir, options: .immediate)
        let reopened = try ProjectPackage(readingFrom: readWrapper)
        #expect(reopened.project == package.project)
        #expect(reopened.imageData(named: "job-1.png") == Data([1, 2, 3, 4]))
    }

    @Test("Removing an image drops it from the package")
    func removingImage() throws {
        let package = ProjectPackage(project: sampleProject())
        package.setImageData(Data([1]), named: "gone.png")
        package.removeImage(named: "gone.png")
        let reopened = try ProjectPackage(readingFrom: try package.fileWrapper())
        #expect(reopened.imageData(named: "gone.png") == nil)
    }

    @Test("Reading a non-directory wrapper throws")
    func readingNonDirectoryThrows() {
        let file = FileWrapper(regularFileWithContents: Data("nope".utf8))
        #expect(throws: ProjectPackage.Error.notADirectory) {
            _ = try ProjectPackage(readingFrom: file)
        }
    }

    @Test("Reading a directory without a manifest throws")
    func readingWithoutManifestThrows() {
        let empty = FileWrapper(directoryWithFileWrappers: [:])
        #expect(throws: ProjectPackage.Error.missingManifest) {
            _ = try ProjectPackage(readingFrom: empty)
        }
    }
}
