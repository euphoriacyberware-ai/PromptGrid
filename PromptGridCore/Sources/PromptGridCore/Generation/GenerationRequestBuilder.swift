//
//  GenerationRequestBuilder.swift
//  PromptGridCore
//
//  The single request-building path every enqueue funnels through (Specification
//  §4.1). Built from the *frozen* `GenerationJob` — its resolved prompts, settings
//  snapshot, and seed — so a first send and a retry produce byte-identical
//  requests (§4). The request `id` is set to the job `id` so results can be
//  correlated back to the cell.
//

import Foundation
import DrawThingsClient
import DrawThingsQueue

public enum GenerationRequestBuilder {

    /// Build the queue request for a job. `referenceImageData` is the prompt's
    /// optional img2img/inpaint source, loaded from the package by the caller.
    public static func request(
        for job: GenerationJob,
        in project: Project,
        referenceImageData: Data? = nil
    ) -> GenerationRequest {
        var configuration = job.settingsSnapshot.configuration
        configuration.seed = Int64(job.seedUsed)   // the run's seed always wins (§4.1)

        let prompt = project.prompts.first { $0.id == job.promptID }
        let run = project.runs.first { $0.id == job.runID }
        let image = referenceImageData.flatMap { PlatformImage.fromData($0) }

        // The shared queue spans every open project, so each row needs enough
        // context to identify itself (§4.1).
        let name = "\(project.name) · Row \((prompt?.order ?? 0) + 1) · Run \(run?.index ?? 0)"

        return GenerationRequest(
            id: job.id,
            prompt: job.resolvedPrompt,
            negativePrompt: job.resolvedNegativePrompt,
            configuration: configuration,
            image: image,
            name: name
        )
    }
}
