# negaflow documentation

Split by subject so you can open the one you need first.

English · [한국어](ko/README.md) · [日本語](ja/README.md) · [简体中文](zh-Hans/README.md) ·
[Français](fr/README.md) · [Deutsch](de/README.md)

```mermaid
flowchart LR
    A["I want to know the product"] --> P["product"]
    B["I want the code and data flow"] --> R["architecture"]
    C["I want formats and numbers"] --> S["reference"]
    D["I want to know if it can ship"] --> V["validation"]
```

> [!NOTE]
> The current version is `1.0.7`. What is built and what was actually checked
> is tracked in [Project status](product/PROJECT_STATUS.md).

## Product

| Document | Read it when |
|---|---|
| [Library to print workflow](product/WORKFLOW.md) | You need import, folder development, copy/paste, and print behavior |
| [Chroma Engine](product/CHROMA_ENGINE.md) | You want the film inversion and develop order |
| [GrainMend](product/GRAINMEND.md) | You want to see how dust and scratch repair works |
| [Film profiles](product/FILM_PROFILES.md) | You want where the bundled profiles came from, and their limits |
| [Project status](product/PROJECT_STATUS.md) | You want the implementation, measurement, and release state |

## Architecture

| Document | What it covers |
|---|---|
| [Product architecture](architecture/PRODUCT_ARCHITECTURE.md) | Data flow between app, engine, storage, and export |
| [Catalog storage](architecture/CATALOG_STORAGE.md) | Why SQLite, the old format, and the measurements |
| [Scanner plugin architecture](architecture/SCANNER_PLUGINS.md) | External process, approval, scan file disclosure |
| [Library archive](architecture/LIBRARY_ARCHIVE.md) | How originals and edit history are stored together |

## Reference

| Document | What it covers |
|---|---|
| [Scanner CLI JSON](reference/CLI_JSON.md) | Output shape of `detect --json` and `capabilities --json` |
| [Render manifest](reference/RENDER_MANIFEST.md) | SHA-256 links between source, edit values, and output file |
| [Print layouts and C-print preview](reference/C_PRINT.md) | Seven layouts, finished-page export, optimized rendering, proof-only ICC behavior, and accuracy limits |
| [Fixed print response](reference/PRINT_RESPONSE.md) | The formula and anchors of `shoulder-print-response-v4` |
| [Scanner profile quality gate](reference/PROFILE_QUALITY_GATE.md) | Release rules for REAL/TARGET pair material |
| [Scanner noise profiles](reference/SCANNER_NOISE_PROFILES.md) | Repeat-scan measurement and when it applies automatically |
| [Film GrainMend IR should avoid](reference/INFRARED_LIMITS.md) | Black and white, Kodachrome, RGB/IR alignment limits |
| [IT8 color validation](reference/IT8_COLOR_VALIDATION.md) | Patch measurement, evidence grades, synthetic regression |

## Validation

| Document | Use it when |
|---|---|
| [Real-device QA checklist](validation/REAL_QA_CHECKLIST.md) | You check a real Mac, display, scanner, and film |
| [GrainMend real scan comparison](validation/GRAINMEND_CORPUS.md) | You measure the 44 FILM-R v2 pairs again |
| [GrainMend IR real scan measurement](validation/GRAINMEND_IR.md) | You measure how much GrainMend IR removes |

## Film simulation research

| Document | Use it when |
|---|---|
| [Color negative still film research](research/film-simulation/01-color-negative-still.md) | You need the C-41 research notes |
| [Color slide film research](research/film-simulation/02-color-slide.md) | You need the E-6 and K-14 research notes |
| [Color motion picture film research](research/film-simulation/03-color-motion-picture.md) | You need the ECN-2 research notes |
| [Digital B&W branch plan](research/film-simulation/08-digital-bw-branch-plan.md) | You need the black-and-white design handoff |
| [Next-session prompt](research/film-simulation/09-handoff-prompt.md) | You are continuing the film-simulation work |
| [Film simulation handoff](research/film-simulation/09-handoff.md) | You need the current implementation handoff |

## Provenance and distribution

| Document | Use it when |
|---|---|
| [Code and resource provenance](legal/PROVENANCE.md) | You check the Apache/GPL boundary and bundled resource hashes |
| [`TRADEMARKS.md`](../TRADEMARKS.md) | You check how film, scanner, and product names are used |

## How these are written

- Product documents describe only what a user sees today.
- Architecture documents describe responsibilities and how data moves.
- Code values, field names, and hashes in reference documents stay as they are.
- Validation documents separate what passed from what is not checked yet.
