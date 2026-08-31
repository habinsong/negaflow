# negaflow documentation

Split by subject so you can open the one you need first.

English · [한국어](ko/README.md) · [日本語](ja/README.md) · [简体中文](zh-Hans/README.md) · [Français](fr/README.md) · [Deutsch](de/README.md)

```mermaid
flowchart LR
    A["I want to know the product"] --> P["product"]
    B["I want the code and data flow"] --> R["architecture"]
    C["I want formats and numbers"] --> S["reference"]
```

> [!NOTE]
> negaflow 1.1.1 runs on macOS and on Windows. The two apps are written separately for their own platform and produce the same picture from the same file.

## Platform

| Document | Read it when |
|---|---|
| [How macOS and Windows differ](platform/PLATFORM_DIFFERENCES.md) | You want to know what is the same on both and what is not |
| [macOS docs](../negaflow-mac/docs/README.md) | You install, build, or use the CLI on macOS |
| [Windows docs](../negaflow-windows/docs/README.md) | You install, build, or check the engine on Windows |

## Product

| Document | Read it when |
|---|---|
| [Library to print workflow](product/WORKFLOW.md) | You need import, folder development, copy/paste, and print behavior |
| [Chroma Engine](product/CHROMA_ENGINE.md) | You want the film inversion and develop order |
| [GrainMend](product/GRAINMEND.md) | You want to see how dust and scratch repair works |
| [Film profiles](product/FILM_PROFILES.md) | You want where the bundled profiles came from, and their limits |

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
| [Flatbed frame detection](reference/FRAME_DETECTION.md) | How film is told from an empty holder, and how cut boundaries are measured |
| [IT8 color validation](reference/IT8_COLOR_VALIDATION.md) | Patch measurement, evidence grades, synthetic regression |

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
- Plain sentences. No marketing adjectives, no closing summary paragraph, no negative parallelism.
- A section that exists in one language exists in all six.
