# PromptGrid

**Batch image generation for [Draw Things](https://drawthings.ai), organized as a grid.**

PromptGrid is a macOS and iOS app that turns Draw Things into a production tool. Instead of generating one image at a time, you lay out your prompts as rows and your seeds as columns, then fill the whole grid in a single queued batch. It's built for iterating on a scene, comparing seeds, and curating the best results across many prompts at once.

PromptGrid talks to a Draw Things server over its gRPC API — the generation happens in Draw Things, PromptGrid drives it and organizes the output.

> **Note:** PromptGrid is a client for Draw Things. You need Draw Things installed with its gRPC server enabled (see [Requirements](#requirements)).

[!CAUTION]: This app is capable of generating very large batch jobs which can result in your account getting throttled by the Draw Things cloud service if used with 'bridge mode'. It is recommended you only run large batches with local generation.

---

## What it does

- **The prompt × seed grid.** Rows are prompts, columns are runs (seeds). Every cell is one image. Add prompts and seed columns freely and generate the intersections.
- **Projects.** Each project is a self-contained `.pgproj` package holding your prompts, settings, and generated images. Projects live in a library folder you choose (kept private on your device by default).
- **Draw Things configuration, verbatim.** Paste a configuration copied straight out of Draw Things into any prompt — model, sampler, steps, guidance, LoRAs, ControlNets, upscaler, and more are all honored. Set project-wide defaults and copy settings to or from any prompt.
- **Prompts with structure.** Each prompt has an optional title, the positive and negative prompt, free-form scene notes, an optional reference image (img2img / inpaint), and its own generation settings.
- **Wildcards.** Use `{option a|option b|option c}` groups in a prompt and each generation picks one at random, frozen into that cell.
- **A real queue.** Watch what's generating, reorder or cancel pending work, retry failures, and pause/resume — all from the queue panel.
- **Batch fill.** "Generate Missing" queues every empty cell at once, in your preferred order, and can skip rows you've already finalized.
- **Ranking & curation.** Rank results as Candidate, Shortlisted, or Final (one Final per row), and filter exports by rank.
- **Lightbox.** Open any cell full-screen with zoom and keyboard navigation across the grid.
- **Multi-select.** Select many cells (⌘/⇧-click on Mac, a Select mode on iPad) and generate, regenerate, rank, or delete them together.
- **Export.** Write a flat folder of PNGs with your prompt and settings embedded as XMP metadata, or export your prompt rows as a reusable `.json` file. Filenames include the project name and prompt title.
- **Import.** Bring a prompts `.json` back in as a new project.

---

## Requirements

- **macOS 26 or later**, or **iOS / iPadOS 26 or later**.
- **Draw Things** with its **gRPC server** running and reachable from the device:
  - In Draw Things, turn on its API / gRPC server ("server mode").
  - Note the **host**, **port** (default `7859`), whether **TLS** is on, and any **shared secret** you've set.
  - The Draw Things server must have the models, LoRAs, and ControlNets referenced by your configurations. (Configuration fields use bare filenames, exactly as Draw Things exports them.)

You can run Draw Things on the same Mac (`127.0.0.1`) or on another machine on your network.

---

## Installation

### Release (macOS)

1. Download the latest `PromptGrid.dmg` from the [Releases](../../releases) page.
2. Open the `.dmg` and **drag `PromptGrid.app` onto the `Applications` link**.
3. Launch PromptGrid from Applications.

### Build from source

PromptGrid is a standard Xcode project with a local Swift package for its core logic.

```bash
git clone https://github.com/euphoriacyberware-ai/PromptGrid.git
cd PromptGrid
open PromptGrid.xcodeproj
```

Then in Xcode:

1. Select the **PromptGrid** scheme.
2. Choose a run destination — **My Mac**, or an iOS/iPadOS simulator or device.
3. **Product → Run** (⌘R).

Xcode resolves the Swift package dependencies automatically on first build. Requires **Xcode 26 or later**.

The project is organized as:

- `PromptGrid/` — the app (SwiftUI views, generation coordinator, app entry point).
- `PromptGridCore/` — a local Swift package with the model, project storage, generation logic, and export/import (fully unit-tested with `swift test`).

---

## Getting started

1. **Connect to Draw Things.** Open **Settings** (⌘,) → **Server** and enter your Draw Things host, port, TLS, and shared secret. Use **Test Connection** to confirm.
2. **Create a project.** Click **New Project** (⌘N) and give it a name.
3. **Add a prompt.** Click **Add Prompt** (⌘⇧A), then click the prompt cell to open the editor. Type your prompt, and paste a Draw Things configuration into the **Configuration** tab (or set project defaults first, in **Project Settings**, so new prompts inherit them).
4. **Add a run.** Click **New Run** (⌘R) to add a seed column. Choose a random or fixed seed.
5. **Generate.** Right-click a cell and choose **Generate**, or use **Generate Missing** (⌘G) to fill the whole grid. Watch progress in the queue.
6. **Curate.** Double-click a cell to open the lightbox. Rank your favorites (Candidate / Shortlisted / Final) from the cell menu or the inspector.
7. **Export.** Click **Export** (⌘⇧E) and choose **Images** (a folder of PNGs) or **Prompts** (a `.json` file), filtered by rank.

### Handy details

- **Reproducing a Draw Things image:** paste the full configuration, set the run's seed to the exact seed, and make sure the **seed mode** matches — these together determine the result.
- **Reference images:** add one in the prompt editor for img2img / inpaint workflows.
- **Row & column tools:** right-click a prompt or a run header to insert, reorder, select, or clear it.
- **Library location:** change where projects are stored in **Settings → Library** (e.g. point it at an iCloud Drive or Dropbox folder to sync — note image libraries can get large).

---

## How it's built

- **SwiftUI**, targeting macOS and iPadOS, in Swift 6 language mode.
- Generation is driven through Draw Things' gRPC API via the `DrawThingsClient` and `DrawThingsQueue` Swift packages.
- Projects are `NSFileWrapper`-based `.pgproj` packages with coordinated file access, so they're safe to keep in synced folders.
- Image metadata is embedded as XMP on export, so your generation settings travel with the file.

---

## License

_TODO: add your license here before release._

---

PromptGrid is an independent project and is not affiliated with Draw Things.
