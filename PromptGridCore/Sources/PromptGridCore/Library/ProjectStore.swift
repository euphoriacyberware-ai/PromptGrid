//
//  ProjectStore.swift
//  PromptGridCore
//
//  The observable editing model for one open project. Holds a mutable `Project`,
//  persists changes back into the `.pgproj` package (preserving image files via
//  the retained `ProjectPackage`), and exposes the grid mutations. Business rules
//  that must stay invariant — e.g. contiguous prompt `order` — live here, not in
//  the views.
//

import Foundation
import Observation

@MainActor
@Observable
public final class ProjectStore {

    public let url: URL
    public private(set) var project: Project
    /// Surfaced to the UI when a save fails.
    public var lastError: String?

    private let package: ProjectPackage

    // MARK: Init

    /// Open the package at `url`.
    public init(contentsOf url: URL) throws {
        self.url = url
        self.package = try FileCoordination.read(at: url) { url in
            let wrapper = try FileWrapper(url: url, options: .immediate)
            return try ProjectPackage(readingFrom: wrapper)
        }
        self.project = package.project
    }

    /// In-memory store, for tests and previews.
    public init(url: URL, package: ProjectPackage) {
        self.url = url
        self.package = package
        self.project = package.project
    }

    // MARK: Persistence

    /// Write the current project back to disk (updating `modifiedAt`).
    public func save() throws {
        project.modifiedAt = Date()
        package.updateProject(project)
        let wrapper = try package.fileWrapper()
        try FileCoordination.write(wrapper, to: url)
    }

    /// Save, routing any failure to `lastError` instead of throwing — convenient
    /// for call sites in view actions.
    public func saveOrReport() {
        do { try save() }
        catch { lastError = error.localizedDescription }
    }

    // MARK: Prompt (row) mutations

    /// Append a new empty prompt seeded with the project's default settings.
    @discardableResult
    public func addPrompt() -> Prompt {
        let prompt = Prompt(
            settings: project.defaultSettings,
            order: project.prompts.count
        )
        project.prompts.append(prompt)
        return prompt
    }

    /// Remove a prompt, delete any of its cell images from the package, and keep
    /// `order` contiguous.
    public func removePrompt(id: UUID) {
        guard let index = project.prompts.firstIndex(where: { $0.id == id }) else { return }
        let removed = project.prompts.remove(at: index)

        for job in removed.jobs.values {
            if let name = job.imageFilename { package.removeImage(named: name) }
            if let name = job.thumbnailFilename { package.removeThumbnail(named: name) }
        }
        if let reference = removed.referenceImageFilename {
            package.removeReference(named: reference)
        }

        renumberPrompts()
    }

    /// Reorder rows (drag-to-reorder in the grid).
    public func movePrompts(fromOffsets: IndexSet, toOffset: Int) {
        project.prompts.move(fromOffsets: fromOffsets, toOffset: toOffset)
        renumberPrompts()
    }

    private func renumberPrompts() {
        for index in project.prompts.indices {
            project.prompts[index].order = index
        }
    }

    // MARK: Cell assets

    public func thumbnailData(for job: GenerationJob) -> Data? {
        guard let name = job.thumbnailFilename else { return nil }
        return package.thumbnailData(named: name)
    }

    public func imageData(for job: GenerationJob) -> Data? {
        guard let name = job.imageFilename else { return nil }
        return package.imageData(named: name)
    }
}
