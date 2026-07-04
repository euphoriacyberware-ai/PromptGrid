import Testing
import Foundation
@testable import PromptGridCore
import DrawThingsClient
import DrawThingsQueue

@MainActor
@Suite("_probe")
struct ConnProbe {
    func runReq(_ req: GenerationRequest, timeout: Int) async -> String {
        let queue = try! DrawThingsQueue(address: "127.0.0.1:7859", useTLS: true)
        return await withCheckedContinuation { cont in
            Task {
                var done = false
                let ev = Task {
                    for await e in queue.events.values {
                        switch e {
                        case .requestProgress(_, let p) where p.currentStep>0: print("PROBE step \(p.currentStep)/\(p.totalSteps)")
                        case .requestCompleted(let r): if !done { done=true; cont.resume(returning: "OK images=\(r.images.count)") }; return
                        case .requestFailed(let er): if !done { done=true; cont.resume(returning: "FAILED \((er.underlyingError as NSError).localizedDescription)") }; return
                        default: break
                        }
                    }
                }
                queue.enqueue(req)
                try? await Task.sleep(for: .seconds(Double(timeout)))
                if !done { done=true; cont.resume(returning: "TIMEOUT") }
                ev.cancel()
            }
        }
    }

    @Test func verifyFix() async throws {
        do { _ = try await DrawThingsService(address: "127.0.0.1:7859", useTLS: true).echo() }
        catch { print("PROBE SERVER DOWN — restart Draw Things"); return }

        let libPath = NSHomeDirectory() + "/Library/Containers/euphoria-ai.PromptGrid/Data/Library/Application Support/euphoria-ai.PromptGrid/Library/Projects/Test Phase 3.pgproj"
        let pkg = try ProjectPackage(readingFrom: try FileWrapper(url: URL(fileURLWithPath: libPath), options: .immediate))
        let project = pkg.project
        guard let prompt = project.prompts.first(where: { !$0.jobs.isEmpty }), let job = prompt.jobs.values.first else { print("PROBE no job"); return }
        let req = GenerationRequestBuilder.request(for: job, in: project, referenceImageData: nil)
        print("PROBE prompt=\(req.prompt.prefix(50))")
        print("PROBE faceRestoration=\(String(describing: req.configuration.faceRestoration)) upscaler=\(String(describing: req.configuration.upscaler)) refiner=\(String(describing: req.configuration.refinerModel))  (should all be nil now)")

        print("PROBE gen1 (exact app request, FIXED) -> \(await runReq(req, timeout: 240))")
        var minimal = DrawThingsConfiguration(); minimal.model = "z_image_turbo_1.0_i8x.ckpt"; minimal.steps = 6; minimal.seed = 9; minimal.width = 512; minimal.height = 512; minimal.guidanceScale = 1
        print("PROBE gen2 (server-alive detector) -> \(await runReq(GenerationRequest(prompt: "a cat", configuration: minimal, name: "det"), timeout: 60))")
    }
}
