# PromptGrid — Specification

> Working title. Rename freely — search/replace "PromptGrid" throughout this doc and the project once a real name is picked.

## 1. Overview

PromptGrid is a macOS + iOS app for managing Draw Things image generation at scale. A project holds a set of **prompts** (rows) and a set of **runs** (columns); each run applies one seed across every prompt, producing a grid of generation results. The app queues generation over Draw Things' gRPC service, stores results in a portable project package, and supports curating (ranking) and exporting the outputs.

**Platforms:** macOS + iOS (iPhone and iPad), single shared codebase where possible.

**Dependencies (Swift Package Manager):**
- [DrawThingsQueue](https://github.com/euphoriacyberware-ai/DrawThingsQueue) — queue orchestration on top of the gRPC client (pending/current/completed state, retry, reorder, pause/resume, cancellation).
- [DT-gRPC-Swift-Client](https://github.com/euphoriacyberware-ai/DT-gRPC-Swift-Client) — `DrawThingsConfiguration`, `GenerationRequest`, `GenerationResult`, `GenerationProgress`, `LoRAConfig`, `ControlConfig`, and the gRPC transport itself.

**Before implementing against either dependency, check out its actual source via SPM and read the real symbol names/signatures.** This document paraphrases their public surface from their documentation; treat any specific property name below as "confirm against source," not as verified truth.

**Minimum versions (recommendation, adjust if the dependencies require otherwise):** macOS 15+, iOS 18+, Swift 6, Xcode 16+.

## 2. Architecture

### 2.1 Document model

Each project is a **package** (a folder that Finder/Files presents as a single file) — plain `Codable` structs serialized to JSON, wrapped in a platform `FileWrapper`. **Do not use SwiftData or CoreData+CloudKit for project storage** — a package needs to stay a real, portable, Finder/Files-visible folder that syncs via iCloud Drive at the file level; SwiftData wants to own an opaque private store, which fights that goal.

- macOS: `NSDocument` subclass, `read(from:ofType:)` / `write(to:ofType:)` operate on the `FileWrapper` directly (`isEntireFileLoaded = false` if the package can get large, to avoid re-reading unchanged images on every save).
- iOS: `UIDocument` subclass, same underlying model and package format.
- Both platforms' document classes are thin — all real model/business logic lives in a shared Swift package (`PromptGridCore` or similar) that both app targets depend on.
- Register the package extension (see §3) as `LSTypeIsPackage = YES` / a custom `UTType` conforming to `.package` in each target's `Info.plist`.

### 2.2 Library

The app is a **library/shoebox app**, not a per-file document app — one window, a sidebar listing every project, no manual File > Open step for day-to-day use (à la Photos or Logic Pro).

- The library is a folder inside the app's iCloud container (e.g. `Library/Projects/`). Projects sync automatically because they're just files in that folder.
- The sidebar's project list is **built by scanning that folder** with `NSMetadataQuery` (which also reports iCloud upload/download status per item, useful for sync indicators) — there is no separate index database to fall out of sync with the folder's real contents.
- Use `NSFileCoordinator` / implement `NSFilePresenter` for any read/write against files in this folder, since iCloud Drive can touch them from another process or device at any time.

### 2.3 gRPC connection

- The Draw Things server address (host + port) is entered manually per device in Settings — no Bonjour/mDNS discovery in v1.
- This setting is **device-local**, not synced via iCloud (a Mac and an iPhone will typically point at different or differently-reachable addresses).
- `DrawThingsQueue` is instantiated **once per app launch**, as a single global/shared object (environment-injected in SwiftUI), not per project — the queue spans every open project simultaneously.
- There is no cross-device queue coordination: if generation is triggered from both a Mac and an iPhone against the same server, each device's queue is independent and the server itself serializes the actual work.
- Draw Things' gRPC responses do not reliably echo the seed back. Never derive the seed used from the response — always generate/choose it client-side before sending the request, and store that value directly.

## 3. Package format

```
MyProject.pgproj/                 (folder, presented as a single file)
  Manifest.json                    JSON-encoded Project (see §4)
  Images/
    <jobID>.png                    full-resolution generated image
  Thumbnails/
    <jobID>.png                    small preview, generated locally on save
  References/
    <promptID>.png                 optional per-prompt reference image (img2img/inpaint source)
```

Images are referenced by job ID by convention; `GenerationJob` still carries explicit filename fields for flexibility (e.g. future format changes).

## 4. Data model

All types below live in the shared package and conform to `Codable`.

```swift
struct Project: Codable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var defaultSettings: DrawThingsConfiguration   // copied into new prompts
    var prompts: [Prompt]                           // ordered — grid rows
    var runs: [Run]                                 // ordered — grid columns
}

struct Prompt: Codable, Identifiable {
    var id: UUID
    var text: String                    // template; may contain {a|b|c} wildcard groups
    var negativePrompt: String
    var settings: DrawThingsConfiguration   // copied from project defaults at creation, then independently editable
    var referenceImageFilename: String?     // optional img2img/inpaint source in References/
    var order: Int
    var jobs: [UUID: GenerationJob]     // keyed by Run.id — one entry per cell that has ever been attempted
}

struct Run: Codable, Identifiable {
    var id: UUID
    var index: Int              // display order / column number, 1-based for UI
    var seed: Int
    var seedWasRandom: Bool     // for display only ("random" vs "fixed" badge) — the value itself is what matters
    var createdAt: Date
}

enum CellRank: String, Codable {
    case candidate, shortlisted, final
}

enum JobStatus: Codable, Equatable {
    case pending
    case generating
    case completed
    case failed(message: String)
    case cancelled
}

struct GenerationJob: Codable, Identifiable {
    var id: UUID
    var runID: UUID
    var promptID: UUID
    var status: JobStatus
    var seedUsed: Int
    var settingsSnapshot: DrawThingsConfiguration   // frozen at generation time — never mutated after
    var resolvedPrompt: String                       // wildcard-resolved text actually sent
    var resolvedNegativePrompt: String
    var rank: CellRank?          // nil until status == .completed
    var imageFilename: String?   // relative to Images/
    var thumbnailFilename: String?  // relative to Thumbnails/
    var createdAt: Date
    var completedAt: Date?
    var retryCount: Int
}
```

**Everything frozen into `GenerationJob` at generation time (settings, resolved prompt, seed) must never be retroactively rewritten** — a completed cell is a historical record of exactly what produced its image, independent of later edits to the prompt or its settings. Retrying a failed job re-sends the *same* frozen `resolvedPrompt`/`settingsSnapshot`/`seedUsed` — it does not re-resolve wildcards or re-copy current settings.

### 4.1 Building a generation request

```swift
func makeRequest(project: Project, prompt: Prompt, run: Run) -> GenerationRequest {
    var config = prompt.settings
    config.seed = run.seed   // always overridden — the JSON editor's "seed" field is display-only, never applied
    return GenerationRequest(
        prompt: WildcardResolver.resolve(prompt.text),
        negativePrompt: WildcardResolver.resolve(prompt.negativePrompt),
        configuration: config,
        image: /* load prompt.referenceImageFilename if set */,
        name: "\(project.name) · Row \(prompt.order + 1) · Run \(run.index)"
    )
}
```

The `name` here matters: since the queue is shared across every open project, each queue row needs enough context to identify itself.

## 5. Wildcards

Prompt and negative-prompt text may contain flat wildcard groups: `{option 1|option 2|option 3}`.

- Resolution is a pure function: find `\{[^{}]+\}`, split each match on `|`, trim whitespace from each option, pick one at random.
- **No nesting** — `{a|{b|c}}` is out of scope; treat malformed groups (unclosed `{`, empty `{}`) as literal text rather than erroring.
- Resolution happens **once, at job creation** (when a run is created, or when a single empty cell is generated) and is frozen into `GenerationJob.resolvedPrompt`/`resolvedNegativePrompt`. Retry reuses the frozen resolution.
- Each prompt resolves independently — the run's seed is shared across prompts, but wildcard picks are not.
- An empty (not-yet-generated) cell displays the raw template, braces and all — never a fake pre-resolved preview.

## 6. UI structure

```
Window
├── Sidebar — project list (scanned from the library folder)
└── Detail — selected project
    ├── Toolbar
    │   ├── + Add prompt (row)
    │   ├── + New run (column) → seed picker popover (§7)
    │   ├── Queue icon w/ pending-count badge → queue popover (§8)
    │   └── Export…  → export sheet (§11)
    ├── Grid
    │   ├── Leftmost column: prompt text (native spellchecked view; static/truncated when not focused)
    │   └── One column per run: thumbnail cells with rank badge overlay
    ├── Inspector sidebar (shown on single-click cell selection) (§9)
    └── Lightbox (shown on double-click cell) (§9)
```

On iPhone, the grid becomes horizontally scrollable rather than switching to a different layout — same rows/columns model everywhere, just denser.

## 7. Runs (columns)

**Add.** Toolbar "+ New run" opens a popover: a Random/Fixed seed toggle. Random shows a freshly-rolled number (visible, so it's recorded even in "random" mode); Fixed lets you type a value or re-roll via a dice button. "Create run" immediately:
1. Creates the `Run` record.
2. For every existing prompt, builds a `GenerationRequest` (§4.1) and enqueues it.

New prompts added after a run already exists show an **empty cell** in that run's column — there's no automatic backfill; the user generates it manually from the cell/lightbox (§9).

**Delete.** Requires confirmation with dynamic copy: "Delete run 2? This deletes N generated images. This can't be undone," where N is the actual completed-image count for that run. On confirm:
1. Call `cancel(id)` on any of that run's jobs still `pending` or the current `generating` job in `DrawThingsQueue`, before removing anything.
2. A result arriving for a job whose run no longer exists (possible if generation couldn't actually be aborted server-side) must be discarded silently by the completion handler — check the run still exists before writing an image or touching the manifest.
3. Remove the `Run` record, its jobs, and the corresponding files under `Images/`/`Thumbnails/`.

## 8. Queue panel

A popover behind the toolbar's queue icon, backed directly by `DrawThingsQueue`'s published state:

- **Generating now** — `currentRequest` + `currentProgress` (stage, live preview image, progress fraction) as a single highlighted row.
- **Pending** — `pendingRequests`, drag-reorderable (`moveRequests(from:to:)` — pending items only, the in-flight one can't be reordered), each row cancellable individually.
- **Needs attention** — `errors`, each showing `canRetry`/`retryCount`/`maxRetries` and a Retry button that calls `retry(id)`.
- Pause/resume control mapped to `pause()`/`resume()`; a banner appears when `isPaused` is true from `lastError` (e.g. connectivity loss), with its own Resume action.

## 9. Grid cell, inspector, and lightbox

**Single click** selects the cell and shows the **inspector** in a persistent sidebar: status, resolved prompt + negative prompt, a compact settings table (model, sampler, steps, size, guidance, seed), rank control, and generated timestamp.

**Double click** opens a **lightbox**: the image (or an empty/failed state) large, with the *same inspector component* reused in a right-hand panel — build the inspector once, place it in two containers.

**Navigation** inside the lightbox is 2D, mirroring the grid axes: left/right move across runs for the same prompt (row fixed), up/down move across prompts for the same run (column fixed). Arrow keys on Mac/iPad; four edge chevron buttons everywhere (needed for touch/iPhone regardless).

Navigation **always** moves to the adjacent cell, regardless of its status — arrows are never disabled and never auto-skip:
- **Empty cell** — placeholder image state; inspector shows the current prompt text/template and the settings + seed that *would* be used (no frozen snapshot exists yet); a **Generate** button enqueues just that one job via the same request-building path as §4.1/§7.
- **Pending/generating** — same live-progress treatment as the grid cell.
- **Failed** — error message shown; inspector shows the frozen snapshot from the failed attempt; a **Retry** button calls `queue.retry(id)` (not a fresh enqueue, so `retryCount` increments correctly).

Both the run-level batch enqueue and this single-cell enqueue must go through the same request-building function, so the queue panel and grid stay consistent regardless of which one fired the request.

## 10. Ranking

`GenerationJob.rank: CellRank?` — `candidate` once a job completes, `shortlisted`, or `final`. Only one job **per prompt** (across all its runs) may be `final` at a time.

This invariant is enforced in exactly one place — a coordinating method, e.g. `Prompt.setFinal(jobID:)` — that finds any other job under the same prompt currently `.final`, demotes it to `.shortlisted`, then promotes the target, as a single atomic mutation. **No other code path sets `.final` directly.** Every UI surface (grid context menu, sidebar inspector, lightbox inspector) calls this same method.

Grid thumbnails carry a small badge reflecting rank (e.g. filled star = final, outline star = shortlisted, none = candidate) so a row's pick is visible without opening the inspector.

## 11. Export

Toolbar "Export…" opens a sheet:
1. **Filter**, chosen at export time: All / Final only / Final + shortlisted — each option shows a live count computed from the project's current ranks.
2. **Destination**: `NSOpenPanel` (`canChooseDirectories = true`, `canChooseFiles = false`) on macOS; `UIDocumentPickerViewController` in folder mode on iOS.

**Before copying**, any image whose file is still an iCloud placeholder must be materialized first: call `startDownloadingUbiquitousItem(at:)` and wait, with a progress indicator, since a large "All images" export could take a while.

**Output**: one flat folder, no sidecar files. Filenames: `{rowIndex}_{slugified-prompt}_{run}_{rankSuffix}.png` — rank suffix omitted for plain `candidate` (e.g. `01_mountain-lake-at-sunset_run2_final.png`, `02_neon-city-street_run1.png`). On collision, append `-2`, `-3`, etc. rather than overwriting.

### 11.1 Embedded metadata (matches Draw Things' own convention)

Verified by inspecting a real Draw Things export: it embeds a PNG `iTXt` chunk with keyword `XML:com.adobe.xmp` (standard Adobe XMP/RDF), **not** a `tEXt` chunk with a custom keyword. This is natively supported by `CGImageMetadata`/`CGImageDestinationAddImageAndMetadata` — no manual PNG chunk construction needed (unlike, for instance, the Automatic1111-ecosystem `parameters` tEXt convention, which *would* require hand-rolled chunk writing since ImageIO's public PNG dictionary only exposes a fixed set of predefined keys and doesn't expose arbitrary custom keywords).

Match the container shape, but populate it with our own data rather than Draw Things' private/undocumented internal schema:

- `xmp:CreatorTool` — this app's name (not "Draw Things" — we didn't generate the pixels through their export path).
- `dc:description` — resolved prompt, followed by a human-readable settings line: `Steps: 30, Sampler: DPM++ 2M Karras, Guidance Scale: 7.5, Seed: 482913, Size: 1024x1024, Model: sd_xl_base_1.0, Strength: 1.0` (plus LoRA lines if any).
- `exif:UserComment` — our own JSON:
  ```json
  {
    "prompt": "...", "negativePrompt": "...",
    "seed": 482913, "rank": "final",
    "project": "...", "run": 2, "generatedAt": "2026-07-02T15:14:00Z",
    "configuration": { "...full DrawThingsConfiguration snapshot..." }
  }
  ```

Reading this back later (parsing the `iTXt` chunk to recover prompt/settings from an exported PNG) is close to free once the writer exists — worth keeping in mind, not required for v1.

## 12. Prompt detail editor

Opened from a prompt row. Split view (side-by-side on macOS/iPad; a top toggle switching between the two panes on iPhone, where side-by-side doesn't fit):

**Left — the non-configuration fields of `GenerationRequest`:**
- Prompt text — multi-line, native spellcheck (§13).
- "Additional settings" below it: negative prompt (same spellchecked component), reference image picker (img2img/inpaint source).

**Right — raw JSON editor for `DrawThingsConfiguration`:**
- Plain monospaced text editor, debounced validation (decode into `DrawThingsConfiguration`, surface errors inline, keep last-valid state until fixed).
- **Deliberately not syntax-highlighted in v1** — keep it a plain text editor; treat highlighting as a separable later enhancement, not something to build now.
- The `seed` field may appear in this JSON (it's a real field on the underlying struct) but the app always ignores it — the run's seed is what's actually used (§4.1). No special UI treatment needed for this — it's simply inert.

## 13. Spellchecking

SwiftUI's `TextEditor`/`TextField` has a known bug on macOS where `isContinuousSpellCheckingEnabled` gets silently reverted to `false` shortly after being turned on, even when set directly on the underlying `NSTextView`. **Do not build the prompt/negative-prompt editors on top of SwiftUI's `TextEditor`.** Instead, build a small shared `NSViewRepresentable` (macOS) / `UIViewRepresentable` (iOS) component wrapping `NSTextView`/`UITextView` directly, with explicit control: spellcheck on, autocorrection off (autocorrecting a stylized prompt term is more often unwanted than helpful — a spellcheck squiggle is a hint, silent autocorrection isn't).

Build this once, reuse it in both the grid's actively-edited cell and the detail editor's left pane.

**Performance**: this only costs anything for text views that actually exist on screen — it isn't a background scan of the whole document. Two things keep it cheap regardless of project size:
1. The grid must be virtualized (`List`/`Table`, or `NSCollectionView`/`UICollectionView`-backed) so off-screen rows are never materialized.
2. Grid cells show static, truncated text by default; only the actively-focused cell swaps in a live editable/spellchecked view (Numbers/Excel-style). This bounds concurrent spellcheck-active views to about one, regardless of whether the project has 10 rows or 10,000.

## 14. Explicitly out of scope for v1

Listed so they aren't accidentally half-built or silently assumed:

- JSON configuration editor syntax highlighting (plain text only, per §12).
- Bonjour/mDNS discovery of the Draw Things server (manual address entry only).
- Cross-device queue coordination (each device's queue is independent; the server serializes).
- Per-cell batch count (one image per job; use another run for variations).
- Destructive in-place regeneration of a completed cell (only failed cells get Retry; a new result requires a new run).
- Nested wildcard groups.
- Reading/re-importing metadata from an externally exported PNG back into a project (the reader is a near-free follow-on to the writer, but not built now).
- Reference-image handling for anything beyond a single optional per-prompt image (masks, multiple controls, etc. — extend `Prompt`/`GenerationRequest` construction later if needed).

## 15. Implementation phases

| # | Phase | Deliverables |
|---|-------|--------------|
| 1 | Project setup | SPM package skeleton, dependencies added, macOS + iOS app targets, shared model package |
| 2 | Data model & document architecture | Codable models (§4), `NSDocument`/`UIDocument` subclasses, package read/write round-trip (§2.1, §3) |
| 3 | Library & sidebar | `NSMetadataQuery` folder scan, project list, create/open/delete project |
| 4 | Grid view | Virtualized grid, static thumbnail cells, add/remove prompt rows |
| 5 | Runs: add & delete | Seed picker popover, run creation enqueue flow, delete confirmation + cancel + orphan-result guard (§7) |
| 6 | Queue integration | Global `DrawThingsQueue` instance, gRPC address settings, request-building function (§4.1), queue popover (§8) |
| 7 | Prompt detail editor | Spellchecked text component, additional settings pane, JSON config editor + validation, wildcards (§5, §12, §13) |
| 8 | Cell interactions | Inspector sidebar, lightbox, 2D navigation, empty/failed states, Generate/Retry (§9) |
| 9 | Ranking | `CellRank`, one-final-per-row enforcement, badges, rank control (§10) |
| 10 | Export | Filter sheet with live counts, folder picker, filenames, XMP metadata writer, iCloud materialization (§11) |
| 11 | iCloud sync & multi-device polish | `NSFilePresenter`/`NSFileCoordinator` correctness, per-device address storage |
| 12 | Polish & QA | Accessibility labels, dark mode check, keyboard shortcuts, empty-state copy |
