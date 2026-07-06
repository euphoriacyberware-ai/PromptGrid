//
//  FileCoordination.swift
//  PromptGridCore
//
//  Thin wrappers over `NSFileCoordinator` for the coordinated reads/writes/deletes
//  the library and the open-project store both need (Specification §2.2). Full
//  `NSFilePresenter` registration is Phase 11; this is the minimum that keeps
//  concurrent access from another process/device consistent.
//

import Foundation

enum FileCoordination {

    static func write(_ wrapper: FileWrapper, to url: URL) throws {
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

    static func delete(at url: URL) throws {
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

    static func move(from source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var thrown: Error?
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: destination, options: .forReplacing,
                               error: &coordinationError) { source, destination in
            do { try FileManager.default.moveItem(at: source, to: destination) }
            catch { thrown = error }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
    }

    static func writeData(_ data: Data, to url: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var thrown: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            do { try data.write(to: url, options: .atomic) }
            catch { thrown = error }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
    }

    static func read<T>(at url: URL, _ body: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var thrown: Error?
        var result: T?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            do { result = try body(url) }
            catch { thrown = error }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
        // `result` is always set unless `body` threw (handled above).
        return result!
    }
}
