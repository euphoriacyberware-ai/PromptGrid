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

    enum ConnectionOutcome: Equatable {
        case success(String)
        case failure(String)
    }

    /// Probe the server with the `echo` RPC (the same call generation makes
    /// first). Tests the *given* settings so the user can verify before saving.
    func testConnection(_ candidate: ServerSettings) async -> ConnectionOutcome {
        do {
            let service = try DrawThingsService(address: candidate.addressString, useTLS: candidate.useTLS)
            let reply = try await service.echo(name: "PromptGrid")
            let models = reply.files.count
            return .success("Connected to \(candidate.addressString) over \(candidate.useTLS ? "TLS" : "plaintext"). Server reports \(models) model file\(models == 1 ? "" : "s").")
        } catch {
            return .failure("\(error.localizedDescription)\n\nTip: Draw Things' gRPC server usually runs in plaintext. If TLS is on, try turning it off (and vice versa).")
        }
    }

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
            log("queue ready for \(settings.addressString) (TLS \(settings.useTLS ? "on" : "off"))")
        } catch {
            queue = nil
            connectionError = error.localizedDescription
            log("queue creation failed: \(error.localizedDescription)")
        }
    }

    // MARK: Active project

    func setActiveStore(_ store: ProjectStore?) {
        activeStore = store
    }

    /// The live store for a project if it's currently open, so editors (e.g.
    /// project settings from the sidebar) act on the same instance the detail
    /// pane shows rather than a stale second copy.
    func openStore(for url: URL) -> ProjectStore? {
        guard let active = activeStore, active.url == url else { return nil }
        return active
    }

    // MARK: Enqueue / cancel (the Phase 5 seam, now live)

    func enqueue(_ jobs: [GenerationJob], for store: ProjectStore) {
        guard let queue else {
            log("enqueue skipped — no queue (server not configured)")
            return
        }
        let project = store.project
        let requests = jobs.map { job -> GenerationRequest in
            let prompt = project.prompts.first { $0.id == job.promptID }
            let referenceData = prompt.flatMap { store.referenceImageData(for: $0) }
            jobToPackageURL[job.id] = store.url
            let request = GenerationRequestBuilder.request(for: job, in: project, referenceImageData: referenceData)
            let c = request.configuration
            log("request \(request.name): model=\(c.model) size=\(c.width)x\(c.height) steps=\(c.steps) sampler=\(c.sampler.rawValue) loras=\(c.loras.count) strength=\(c.strength) refImage=\(request.image != nil)")
            return request
        }
        log("enqueueing \(requests.count) request(s) to \(settings.addressString)")
        queue.enqueue(requests)
    }

    private func log(_ message: String) {
        print("[PromptGrid] \(message)")
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
        case .requestAdded(let request):
            log("added: \(request.name)")
        case .requestStarted(let request):
            log("started: \(request.name)")
            route(request.id) { $0.markGenerating(jobID: request.id) }
        case .requestCompleted(let result):
            log("completed: \(result.request.name)")
            applyResult(result)
        case .requestFailed(let error):
            let message = (error.underlyingError as NSError).localizedDescription
            log("FAILED: \(error.request.name) — \(message)")
            route(error.id) { $0.markFailed(jobID: error.id, message: message) }
            // Keep the routing entry — a retry reuses the same request id.
        case .requestCancelled(let id):
            log("cancelled: \(id)")
            route(id) { $0.markCancelled(jobID: id) }
            finish(id)
        case .requestRemoved(let id):
            finish(id)
        case .requestProgress:
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
