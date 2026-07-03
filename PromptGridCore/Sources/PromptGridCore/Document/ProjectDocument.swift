//
//  ProjectDocument.swift
//  PromptGridCore
//
//  Thin platform document subclasses (Specification §2.1). All real read/write
//  logic lives in `ProjectPackage`; these just adapt it to `NSDocument`
//  (macOS) and `UIDocument` (iOS / visionOS). The library/shoebox app (§2.2)
//  drives these directly rather than through a document-based scene.
//

import Foundation

#if os(macOS)
import AppKit

public final class ProjectDocument: NSDocument {
    // `read(from:)` / `fileWrapper(ofType:)` are nonisolated and may run off the
    // main thread; NSDocument serializes them against each other, so unsynchronized
    // access to this backing store is safe.
    nonisolated(unsafe) public var package: ProjectPackage?

    public override init() {
        super.init()
    }

    /// Don't hold the whole package in memory — leave unchanged image files on
    /// disk so saves don't rewrite them (Specification §2.1).
    public override var isEntireFileLoaded: Bool { false }

    public override class var autosavesInPlace: Bool { true }

    public override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        package = try ProjectPackage(readingFrom: fileWrapper)
    }

    public override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        guard let package else { throw ProjectPackage.Error.missingManifest }
        return try package.fileWrapper()
    }

    // No window controllers yet — the library app hosts project UI itself.
    public override func makeWindowControllers() {}
}

#elseif os(iOS) || os(visionOS)
import UIKit

public final class ProjectDocument: UIDocument {
    // See the macOS note above: UIDocument's load/contents run off the main
    // thread and are serialized by UIDocument.
    nonisolated(unsafe) public var package: ProjectPackage?

    public override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let wrapper = contents as? FileWrapper else {
            throw ProjectPackage.Error.notADirectory
        }
        package = try ProjectPackage(readingFrom: wrapper)
    }

    public override func contents(forType typeName: String) throws -> Any {
        guard let package else { throw ProjectPackage.Error.missingManifest }
        return try package.fileWrapper()
    }
}
#endif
