# PromptGrid — Claude Code guide

Companion to `PromptGrid-Specification.md`. Read the full spec before writing code — this file is a fast-reference layer on top of it, not a replacement.

## Key facts

| | |
|---|---|
| Platforms | macOS + iOS (iPhone and iPad) |
| Min versions | macOS 15+, iOS 18+, Swift 6, Xcode 16+ (adjust if dependencies require otherwise) |
| Dependencies | [DrawThingsQueue](https://github.com/euphoriacyberware-ai/DrawThingsQueue), [DT-gRPC-Swift-Client](https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client) — via SPM |
| App shape | Single-window library app (sidebar of projects), not per-file documents |
| Storage | Codable + `FileWrapper`-backed `NSDocument`/`UIDocument`, package format — **not** SwiftData/CoreData |
| Package extension | `.pgproj` (placeholder — rename with the app) |
| Sync | iCloud Drive, library folder scanned with `NSMetadataQuery` |
| Queue | One global `DrawThingsQueue` instance for the whole app, shared across all open projects |

## Starting a session

```
I'm building PromptGrid (working title — see the spec for the real name once
picked), a macOS + iOS app for queuing Draw Things image generation across a
grid of prompts × runs. Read PromptGrid-Specification.md in full before
writing any code.

We're starting Phase <N>: <phase name from the table below>.

<specific ask for this session>
```

Point Claude Code at the actual checked-out source of `DrawThingsQueue` and `DT-gRPC-Swift-Client` (via SPM) before it writes code that touches their types — the spec paraphrases their public surface and should not be trusted over the real source for exact property/method names.

## Phase checklist

- [ ] 1. Project setup — SPM package skeleton, dependencies, app targets, shared model package
- [ ] 2. Data model & document architecture
- [ ] 3. Library & sidebar
- [ ] 4. Grid view
- [ ] 5. Runs: add & delete
- [ ] 6. Queue integration
- [ ] 7. Prompt detail editor (spellcheck, additional settings, JSON config, wildcards)
- [ ] 8. Cell interactions (inspector, lightbox, navigation, empty/failed states)
- [ ] 9. Ranking
- [ ] 10. Export
- [ ] 11. iCloud sync & multi-device polish
- [ ] 12. Polish & QA

## Architectural decisions — do not deviate

These were each decided deliberately, several after correcting an earlier assumption. Don't relitigate them mid-implementation without flagging it explicitly.

1. **Codable + `FileWrapper` documents, not SwiftData/CloudKit.** The package must stay a real, portable, Finder/Files-visible folder.
2. **One global `DrawThingsQueue` instance**, not one per project. Every enqueued request needs an explicit project/run/prompt-derived `name` so the shared queue panel stays legible.
3. **The client always generates/owns the seed.** Never read it back from a gRPC response — Draw Things doesn't reliably echo it.
4. **Everything frozen into a `GenerationJob` at generation time stays frozen** — settings snapshot, resolved prompt/negative prompt, seed. Editing a prompt's template or settings later never rewrites a completed job's record. Retry re-sends the frozen values, it does not re-resolve or re-copy anything.
5. **The JSON configuration editor is plain text in v1** — no syntax highlighting. Don't add it speculatively.
6. **Prompt/negative-prompt text fields are a custom `NSViewRepresentable`/`UIViewRepresentable` wrapping `NSTextView`/`UITextView` directly** — not SwiftUI's `TextEditor`, which has a known bug reverting continuous spellchecking to off.
7. **One-`final`-per-row is enforced through a single coordinating method** (e.g. `Prompt.setFinal(jobID:)`). No call site sets `.final` on a job directly.
8. **Export metadata matches Draw Things' own container format** (XMP via a PNG `iTXt` chunk, written through `CGImageMetadata`) but uses this app's own JSON schema inside `exif:UserComment` — not Draw Things' private/undocumented internal schema.
9. **No cross-device queue coordination.** Each device's `DrawThingsQueue` talks independently to whatever server address is configured on that device.
10. **Manual gRPC server address entry only** — no Bonjour discovery in v1.
11. **Grid cells are static/truncated by default**, swapping to a live editable view only when focused — this, plus a virtualized grid container, is what keeps spellchecking cheap regardless of project size. Don't build every cell as a live `NSTextView` up front.

## Quick reference — request building

The one function every enqueue path (run creation, single-cell Generate, Retry) should funnel through:

```swift
func makeRequest(project: Project, prompt: Prompt, run: Run) -> GenerationRequest {
    var config = prompt.settings
    config.seed = run.seed
    return GenerationRequest(
        prompt: WildcardResolver.resolve(prompt.text),
        negativePrompt: WildcardResolver.resolve(prompt.negativePrompt),
        configuration: config,
        image: /* prompt.referenceImageFilename, if set */,
        name: "\(project.name) · Row \(prompt.order + 1) · Run \(run.index)"
    )
}
```

See `PromptGrid-Specification.md` §4.1 for context.
