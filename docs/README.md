# negaflow documentation

Split by subject so you can open the one you need first.

English · [한국어](ko/README.md) · [日本語](ja/README.md) · [简体中文](zh-Hans/README.md) · [Français](fr/README.md) · [Deutsch](de/README.md)

> [!NOTE]
> negaflow 1.2.6 runs on macOS and Windows. The two apps are written separately and produce the same picture from the same file.

## Platform

| Document | Read it when |
|---|---|
| [How the macOS and Windows versions differ](platform/PLATFORM_DIFFERENCES.md) | You want to know what is the same on both and what is not |
| [macOS docs](../negaflow-mac/docs/README.md) | You install, build or use the CLI on macOS |
| [Windows docs](../negaflow-windows/docs/README.md) | You install, build or check the engine on Windows |

## Product

| Document | Read it when |
|---|---|
| [Library to print workflow](product/WORKFLOW.md) | You need import, folder development, copy and paste, or print behavior |
| [Chroma Engine](product/CHROMA_ENGINE.md) | You want the film inversion and develop order |
| [GrainMend](product/GRAINMEND.md) | You want to know how dust and scratch repair works |
| [Film profiles](product/FILM_PROFILES.md) | You want to know where the bundled profiles came from and their limits |

## Architecture

| Document | What it covers |
|---|---|
| [Product architecture](architecture/PRODUCT_ARCHITECTURE.md) | Data flow between app, engine, storage and export |
| [Catalog storage](architecture/CATALOG_STORAGE.md) | SQLite catalog, import of the older JSON catalog, measurements |
| [Scanner plugin architecture](architecture/SCANNER_PLUGINS.md) | External process, approval, scan file publication |
| [Library archive](architecture/LIBRARY_ARCHIVE.md) | Originals and edit history stored together |

## Reference

| Document | What it covers |
|---|---|
| [Scanner CLI JSON](reference/CLI_JSON.md) | Output of `detect --json` and `capabilities --json` |
| [Render manifest](reference/RENDER_MANIFEST.md) | SHA-256 links between source, edit values and output file |
| [Print layouts and C-print preview](reference/C_PRINT.md) | Eight layouts, finished-page export, proof-only ICC, accuracy limits |
| [Negative response](reference/PRINT_RESPONSE.md) | Formula and anchors of `shoulder-print-response-v4` |
| [Scanner profile quality gate](reference/PROFILE_QUALITY_GATE.md) | Release rules for REAL/TARGET pair material |
| [Scanner noise profiles](reference/SCANNER_NOISE_PROFILES.md) | Repeat-scan measurement and when it applies |
| [Film GrainMend IR should avoid](reference/INFRARED_LIMITS.md) | Black and white, Kodachrome, RGB/IR alignment limits |
| [How flatbed frame detection finds film](reference/FRAME_DETECTION.md) | Film versus empty holder, cut boundaries |
| [IT8 color validation](reference/IT8_COLOR_VALIDATION.md) | Patch measurement, evidence grades, synthetic regression |

## Provenance and distribution

| Document | Use it when |
|---|---|
| [Code and resource provenance](legal/PROVENANCE.md) | You check the Apache/GPL boundary or bundled resource hashes |
| [`TRADEMARKS.md`](../TRADEMARKS.md) | You check how film, scanner and product names are used |

## How these are written

- Product documents describe what a user sees today.
- Architecture documents describe responsibilities and data flow.
- Reference documents keep code values, field names and hashes as they are.
- Validation documents separate what passed from what is not checked.
- A section that exists in one language exists in all six.
