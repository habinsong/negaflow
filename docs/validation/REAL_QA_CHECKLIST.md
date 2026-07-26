# Real-device QA checklist

[Docs home](../README.md)

These are the items automated tests and builds cannot confirm.
The final look on screen and the real hardware are checked by the user.
A release candidate is approved only when every applicable required item has a result and its
evidence.

Write each result as `PASS`, `FAIL`, `BLOCKED`, or `N/A`.
`FAIL`, `BLOCKED`, and `N/A` need a reason.

> [!IMPORTANT]
> A build without this table filled in is not marked as checked for real hardware, final image
> quality, signing, or notarization. Passing automated tests is not the same thing.

## Run record

- Release candidate:
- App version and build:
- Commit or source copy:
- macOS version:
- Mac model, architecture, memory:
- Display, scale, HDR state:
- Scanner plugin version:
- Scanner model and connection:
- Checked by:
- Date:

## 1. Install and first launch

| Result | What to check | Evidence or problem |
|---|---|---|
|  | The ZIP/DMG checksum matches the published value. |  |
|  | On a clean user account it copies to `/Applications` and launches. |  |
|  | Gatekeeper shows the expected signer and notarization state. |  |
|  | First launch creates only the app data the documentation lists. |  |
|  | With no scanner plugin, no fake device or capability turns on. |  |
|  | App info, version, build, license, and help are right. |  |

## 2. Import, develop, export

Use at least one JPEG, one TIFF, a DNG/RAW the current decoder reads, and a high-resolution file.
Record the source SHA-256 before and after the run.

| Result | What to check | Evidence or problem |
|---|---|---|
|  | The source bytes are the same before and after import. |  |
|  | The duplicate import warning and its choices are easy to follow. |  |
|  | The starting state is manual correction with the `main` target. |  |
|  | Crop, orientation, tone, color, detail, local adjustment, and undo work as expected. |  |
|  | The original/developed comparison and the clipping display match the export. |  |
|  | JPEG and 16-bit TIFF open, and their metadata is right. |  |
|  | Name conflicts, cancel, failure, and resume never leave part of the files marked as done. |  |
|  | When required edit history or cache is missing, it errors instead of exporting the source. |  |

## 3. Catalog, backup, offline originals

| Result | What to check | Evidence or problem |
|---|---|---|
|  | Relaunching brings back frames, selection, rolls and collections, ratings, and edits. |  |
|  | Cutting a save short still leaves the last healthy catalog and backup. |  |
|  | A missing or broken catalog stops at the recovery screen instead of opening empty. |  |
|  | Creating a backup, previewing a restore, restoring, and relaunching all work. |  |
|  | Offline originals are marked clearly, and the source is not exported in their place. |  |
|  | The correct original relinks and a different file is refused. |  |
|  | Removing from the library does not delete the original. |  |
|  | Moving to Trash is a deliberate choice and stays clear when virtual copies exist. |  |

## 4. Windows, display, accessibility

Check the minimum window size, a large window, Retina scale, Reduce Motion, Increase Contrast,
VoiceOver, full keyboard access, and one language other than Korean.

| Result | What to check | Evidence or problem |
|---|---|---|
|  | Buttons in the sidebar, canvas, inspector, sheets, settings, and help are not cut off. |  |
|  | Resizing the window keeps panel width and canvas focus usable. |  |
|  | Relaunching restores the supported screen layout. |  |
|  | Text never drops below the set size and important values are not truncated. |  |
|  | Sliders, wheels, curves, split buttons, toggles, and selections can be read. |  |
|  | VoiceOver names, values, hints, increments, and selection changes are right. |  |
|  | Keyboard order follows the visual flow and focus is not trapped. |  |
|  | Reduce Motion removes needless movement, and Increase Contrast stays readable. |  |
|  | Product copy changes language while technical IDs stay as they are. |  |
|  | Liquid Glass surfaces show no visible shadow. |  |

## 5. External plugins and real scanners

The SANE implementation is installed and configured from the separate `negaflow-scanner-sane`
release.
Plugin and device evidence goes in that repository and in this record.

| Result | What to check | Evidence or problem |
|---|---|---|
|  | A plugin seen for the first time has to be approved by the user. |  |
|  | Deleting or replacing a plugin voids the earlier approval. |  |
|  | Device discovery shows only the real devices the plugin reported. |  |
|  | Resolution, bit depth, mode, area, preview, exposure, and IR show only reported capabilities. |  |
|  | Unsupported capabilities are hidden or give an accurate reason for being off. |  |
|  | Preview, full scan, cancel, timeout, disconnect, and plugin shutdown all end safely. |  |
|  | The result size, bit depth, area, and applied settings match what was reported. |  |
|  | CLI `detect --json` and `capabilities <id> --json` agree with the app screen. |  |
|  | Plugin files, dependencies, configuration, and logs live outside the app and this repository. |  |

## 6. GrainMend and image quality

Cover color negative, supported dye-based black and white, ordinary silver black and white, slides,
clean frames, dust, scratches, grain, faces, sky, and fine patterns.

| Result | What to check | Evidence or problem |
|---|---|---|
|  | GrainMend is not presented as the same thing as third-party hardware IR cleaning. |  |
|  | Target defects go down without wrecking texture and edges. |  |
|  | False detections on clean frames stay acceptable. |  |
|  | RGB and IR line up, and misaligned or unsupported film fails clearly. |  |
|  | IR keeps to the film-type limits and preserves the source material. |  |
|  | Before and after 100% crops and masks are kept with the settings and app version. |  |

## 7. Performance and memory

| Result | What to check | Evidence or problem |
|---|---|---|
|  | Repeated adjustment and panning on a 24 MP photo stays usable. |  |
|  | Repeated adjustment and panning on a 48 MP photo stays usable. |  |
|  | Develop and export finish at 3600 DPI and 7200 DPI scan sizes. |  |
|  | Working through a 48-frame roll never mixes state between frames. |  |
|  | Under memory pressure only unselected caches are dropped and the current frame stays. |  |
|  | Search, filter, and sort on a large catalog stay usable on the Mac under test. |  |
|  | Heat, memory, and disk use during long jobs are recorded. |  |

## 8. Upgrade and release

| Result | What to check | Evidence or problem |
|---|---|---|
|  | Existing catalogs and sidecars survive the upgrade. |  |
|  | Unsupported older versions and schemas fail safely and say how to recover. |  |
|  | The release bundle has the app, dSYM, checksums, license, and the lists it needs. |  |
|  | Test material, originals, credentials, and the plugin implementation are not in the bundle. |  |
|  | Known issues and device/profile evidence match the release notes. |  |

Release decision: `APPROVE`, `REJECT`, `BLOCKED`

- Decision:
- Blocking issue IDs:
- Accepted non-blocking issue IDs and why:
- Where the evidence is kept:
- Signature:

Any of the following reproduces means an automatic `REJECT` until it is fixed and checked again.

- Changing the source
- Quietly resetting the catalog
- Falling back to the source when an export fails
- Showing fake scanner capabilities
- Publishing only part of the output
- A signing or notarization mismatch
- Data loss
