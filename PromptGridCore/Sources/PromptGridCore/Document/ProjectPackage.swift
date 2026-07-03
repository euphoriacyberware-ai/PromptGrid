//
//  ProjectPackage.swift
//  PromptGridCore
//
//  The `FileWrapper` <-> model bridge for a `.pgproj` package (Specification
//  §2.1, §3). This holds all the real read/write logic so the platform document
//  classes (`ProjectDocument`) stay thin. It is Foundation-only, so it builds
//  and unit-tests identically on macOS and iOS.
//
//  Package layout:
//      MyProject.pgproj/
//        Manifest.json        JSON-encoded Project
//        Images/<jobID>.png
//        Thumbnails/<jobID>.png
//        References/<promptID>.png
//
//  The root directory wrapper is retained across reads and writes so that on
//  save only the manifest is rewritten and unchanged image files are left in
//  place (supports `NSDocument.isEntireFileLoaded == false`).
//

import Foundation

public final class ProjectPackage {

    // MARK: Names

    public static let manifestFilename = "Manifest.json"
    public static let imagesDirectory = "Images"
    public static let thumbnailsDirectory = "Thumbnails"
    public static let referencesDirectory = "References"

    public enum Error: Swift.Error, Equatable {
        case notADirectory
        case missingManifest
        case manifestNotReadable
    }

    // MARK: State

    public private(set) var project: Project

    /// The backing directory wrapper. Rebuilt lazily; retained so image
    /// children survive an incremental save untouched.
    private var root: FileWrapper

    // MARK: Encoding

    /// Manifest JSON is human-readable and portable: dates are ISO 8601
    /// (second precision — sub-second precision is intentionally not preserved).
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: Init

    /// Start a new, empty package for a project.
    public init(project: Project) {
        self.project = project
        self.root = FileWrapper(directoryWithFileWrappers: [:])
    }

    /// Read an existing package from its root directory wrapper.
    public init(readingFrom root: FileWrapper) throws {
        guard root.isDirectory else { throw Error.notADirectory }
        guard let manifest = root.fileWrappers?[Self.manifestFilename] else {
            throw Error.missingManifest
        }
        guard let data = manifest.regularFileContents else {
            throw Error.manifestNotReadable
        }
        self.project = try Self.makeDecoder().decode(Project.self, from: data)
        self.root = root
    }

    // MARK: Model access

    public func updateProject(_ project: Project) {
        self.project = project
    }

    /// Encode the current project into `Manifest.json`.
    public func manifestData() throws -> Data {
        try Self.makeEncoder().encode(project)
    }

    /// Build/refresh the root directory wrapper: rewrite `Manifest.json`, ensure
    /// the three asset subdirectories exist, and preserve existing image files.
    public func fileWrapper() throws -> FileWrapper {
        // Replace the manifest.
        if let existing = root.fileWrappers?[Self.manifestFilename] {
            root.removeFileWrapper(existing)
        }
        let manifest = FileWrapper(regularFileWithContents: try manifestData())
        manifest.preferredFilename = Self.manifestFilename
        root.addFileWrapper(manifest)

        // Ensure asset directories exist.
        _ = directory(Self.imagesDirectory)
        _ = directory(Self.thumbnailsDirectory)
        _ = directory(Self.referencesDirectory)

        return root
    }

    // MARK: Image files

    public func imageData(named filename: String) -> Data? {
        assetData(in: Self.imagesDirectory, named: filename)
    }

    public func thumbnailData(named filename: String) -> Data? {
        assetData(in: Self.thumbnailsDirectory, named: filename)
    }

    public func referenceData(named filename: String) -> Data? {
        assetData(in: Self.referencesDirectory, named: filename)
    }

    public func setImageData(_ data: Data, named filename: String) {
        setAssetData(data, in: Self.imagesDirectory, named: filename)
    }

    public func setThumbnailData(_ data: Data, named filename: String) {
        setAssetData(data, in: Self.thumbnailsDirectory, named: filename)
    }

    public func setReferenceData(_ data: Data, named filename: String) {
        setAssetData(data, in: Self.referencesDirectory, named: filename)
    }

    public func removeImage(named filename: String) {
        removeAsset(in: Self.imagesDirectory, named: filename)
    }

    public func removeThumbnail(named filename: String) {
        removeAsset(in: Self.thumbnailsDirectory, named: filename)
    }

    public func removeReference(named filename: String) {
        removeAsset(in: Self.referencesDirectory, named: filename)
    }

    // MARK: Private helpers

    /// Fetch (creating if needed) a child directory wrapper of the root.
    @discardableResult
    private func directory(_ name: String) -> FileWrapper {
        if let existing = root.fileWrappers?[name], existing.isDirectory {
            return existing
        }
        // Remove a stale non-directory of the same name, if any.
        if let stale = root.fileWrappers?[name] {
            root.removeFileWrapper(stale)
        }
        let dir = FileWrapper(directoryWithFileWrappers: [:])
        dir.preferredFilename = name
        root.addFileWrapper(dir)
        return dir
    }

    private func assetData(in directoryName: String, named filename: String) -> Data? {
        root.fileWrappers?[directoryName]?.fileWrappers?[filename]?.regularFileContents
    }

    private func setAssetData(_ data: Data, in directoryName: String, named filename: String) {
        let dir = directory(directoryName)
        if let existing = dir.fileWrappers?[filename] {
            dir.removeFileWrapper(existing)
        }
        let file = FileWrapper(regularFileWithContents: data)
        file.preferredFilename = filename
        dir.addFileWrapper(file)
    }

    private func removeAsset(in directoryName: String, named filename: String) {
        guard let dir = root.fileWrappers?[directoryName],
              let existing = dir.fileWrappers?[filename] else { return }
        dir.removeFileWrapper(existing)
    }
}
