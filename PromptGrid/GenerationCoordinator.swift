//
//  GenerationCoordinator.swift
//  PromptGrid
//
//  The single, app-wide generation hub (Specification §2.3, §4.1). Owns the one
//  `DrawThingsQueue` instance, the device-local server address, and the routing
//  of queue results back to the right project package — even one that isn't the
//  frontmost open project, since the shared queue spans every project.
//

import SwiftUI
import Combine
import PromptGridCore

@MainActor
final class GenerationCoordinator: ObservableObject {

    /// The one queue for the whole app. `nil` until a server address is set.
    @Published private(set) var queue: DrawThingsQueue?
    @Published private(set) var settings: ServerSettings
    /// Set when the configured address can't be used (e.g. malformed).
    @Published private(set) var connectionError: String?

    /// jobID → the package that owns it, captured at enqueue so results route
    /// correctly regardless of which project is currently open.
    private var jobToPackageURL: [UUID: URL] = [:]
    private weak var activeStore: ProjectStore?
    private var consumeTask: Task<Void, Never>?

    private let thumbnailMaxDimension: CGFloat = 256

    init() {
        settings = ServerSettings.load()
        rebuildQueue()
    }

    var isConfigured: Bool { settings.isConfigured }

    // MARK: Settings

    func updateSettings(_ new: ServerSettings) {
        settings = new
        new.save()
        rebuildQueue()
    }

    private func rebuildQueue() {
        consumeTask?.cancel()
        consumeTask = nil

        guard settings.isConfigured else {
            queue = nil
            connectionError = nil
            return
        }
        do {
            let queue = try DrawThingsQueue(
                address: settings.addressString,
                useTLS: settings.useTLS,
                sharedSecret: settings.sharedSecret.isEmpty ? nil : settings.sharedSecret
            )
            self.queue = queue
            connectionError = nil
            startConsuming(queue)
        } catch {
            queue = nil
            connectionError = error.localizedDescription
        }
    }

    // MARK: Active project

    func setActiveStore(_ store: ProjectStore?) {
        activeStore = store
    }

    // MARK: Enqueue / cancel (the Phase 5 seam, now live)

    func enqueue(_ jobs: [GenerationJob], for store: ProjectStore) {
        guard let queue else { return } // not configured — cells stay pending
        let project = store.project
        let requests = jobs.map { job -> GenerationRequest in
            let prompt = project.prompts.first { $0.id == job.promptID }
            let referenceData = prompt.flatMap { store.referenceImageData(for: $0) }
            jobToPackageURL[job.id] = store.url
            return GenerationRequestBuilder.request(for: job, in: project, referenceImageData: referenceData)
        }
        queue.enqueue(requests)
    }

    func cancel(jobIDs: [UUID]) {
        guard let queue else { return }
        for id in jobIDs { _ = queue.cancel(id: id) }
    }

    /// Retry a failed cell. In-session this is `queue.retry` so the queue's
    /// retryCount increments (§9). If the queue no longer knows the request
    /// (e.g. after relaunch — queue state isn't persisted), rebuild it from the
    /// frozen job and enqueue afresh.
    func retry(_ job: GenerationJob, in store: ProjectStore) {
        if let queue, queue.retry(job.id) { return }
        enqueue([job], for: store)
    }

    // MARK: Result routing

    private func startConsuming(_ queue: DrawThingsQueue) {
        consumeTask = Task { [weak self] in
            for await event in queue.events.values {
                guard let self else { break }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: JobEvent) {
        switch event {
        case .requestStarted(let request):
            route(request.id) { $0.markGenerating(jobID: request.id) }
        case .requestCompleted(let result):
            applyResult(result)
        case .requestFailed(let error):
            let message = (error.underlyingError as NSError).localizedDescription
            route(error.id) { $0.markFailed(jobID: error.id, message: message) }
            // Keep the routing entry — a retry reuses the same request id.
        case .requestCancelled(let id):
            route(id) { $0.markCancelled(jobID: id) }
            finish(id)
        case .requestRemoved(let id):
            finish(id)
        case .requestAdded, .requestProgress:
            break
        }
    }

    private func applyResult(_ result: GenerationResult) {
        let id = result.request.id // set to the job id at build time
        guard let image = result.images.first, let png = image.pngData() else {
            route(id) { $0.markFailed(jobID: id, message: "No image was returned.") }
            finish(id)
            return
        }
        let thumbnail = thumbnailData(from: image) ?? png
        route(id) { $0.applyResult(jobID: id, imageData: png, thumbnailData: thumbnail) }
        finish(id)
    }

    /// Apply a mutation to whichever store owns the job — the live front store if
    /// it's the one, otherwise the on-disk package (load-modify-save).
    private func route(_ jobID: UUID, _ apply: (ProjectStore) -> Bool) {
        guard let url = jobToPackageURL[jobID] else { return }
        if let active = activeStore, active.url == url {
            if apply(active) { active.saveOrReport() }
        } else if let store = try? ProjectStore(contentsOf: url) {
            if apply(store) { store.saveOrReport() }
        }
    }

    private func finish(_ jobID: UUID) {
        jobToPackageURL.removeValue(forKey: jobID)
    }

    private func thumbnailData(from image: PlatformImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image.pngData() }
        let scale = min(thumbnailMaxDimension / size.width, thumbnailMaxDimension / size.height, 1)
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return ImageHelpers.resizeImage(image, to: target).pngData()
    }
}
