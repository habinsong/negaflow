# Library to print workflow

[Docs home](../README.md)

This guide covers import, folder development, settings transfer, scanner thumbnails, and print
output. A library folder follows the physical parent folder of each source; it is not only a
catalog label.

> [!IMPORTANT]
> Source files stay unchanged unless you explicitly move a photo to another folder. Removing a
> folder from the library and deleting a file in Finder are separate actions.

## Import

Import shows a progress bar, percentage, completed count, and total count below the import
controls. Metadata is read off the main thread, then the new frames are registered together so a
large folder does not repeatedly rebuild the library index.

Automatic development of imported photos is **off by default**.

1. The source is registered.
2. Its original thumbnail and folder appear first.
3. Development starts when you apply a process and target to the folder or enter Develop.

To develop every import automatically, enable **Settings → Workflow → Develop imported images
automatically**. The choice persists between launches.

Automatic import development applies only to frames registered by that import. It does not replace
an existing developed state. Reprocessing developed photos happens only after an explicit folder
**Apply** or settings paste.

Scanner captures are different. Their film type, process, and target are already chosen during the
scan, so development starts after the scan result is published. Develop and Print filmstrips use a
developed thumbnail for color negative, slide, black-and-white negative, and black-and-white
positive sources. Library keeps the source thumbnail for source review.

## Folder list

- Collapsed and expanded states persist. Creating a folder or reopening the app does not expand
  the other folders.
- Every folder row has the same `×` control. It removes that folder and its photos from the
  **library only**; source files remain in Finder.
- The photo list inside a folder in Develop has its own height-limited scroll area. A long list or
  small window does not push the rest of the sidebar away.

### Moving photos to another folder

Drag one photo or a selection to another folder row to move the physical files and update the
catalog together. The same rule applies to imported folders, app-created folders, and folders that
contain scanner captures.

An existing destination name never causes an overwrite. If `frame.tiff` exists, negaflow tries
`frame 2.tiff`, then `frame 3.tiff`, and so on. An IR companion of a scanner source moves in the
same transaction.

### Finder changes

negaflow watches the registered physical source folders. After a short debounce, it rescans only
the changed folder when it sees:

- A source file move or rename
- A registered folder move or rename
- A new image directly inside a registered folder

When the source's persistent bookmark resolves the new location, the existing frame is relinked.
A moved folder keeps its folder ID and added date. A newly added file is imported without creating
duplicates for files that are already known.

This is event-driven folder monitoring, not a periodic full-library scan. Frames with the same
physical parent share one watch, and only folders that report a change are inspected.

## Development by folder

Choose a process and target beside the folder title, then select **Apply**. There is no separate
on/off switch.

Apply rerenders every photo in the folder, including photos that were developed earlier. The new
process and target are used while other user adjustments, such as exposure and contrast, remain.
If a frame is already rendering, the folder job waits for that render to finish.

A progress bar, percentage, completed count, and total count appear beside Apply. Large batches
keep only as many workers as there are render slots instead of starting one task per photo.

## Presets and copy/paste

Develop settings are divided into five transferable groups.

| Group | Values |
|---|---|
| Base | Film type and process, target, scanner profile, film base, Auto Levels and neutral balance |
| Tone | Exposure, contrast, density, highlights, shadows, whites, blacks, and tone curves |
| Color | Temperature, tint, color depth, saturation, mixer, grading, calibration, B&W toning, and film emulation |
| Detail | Grain, sharpness, halation, clarity, vignette, noise reduction, GrainMend, and local adjustments |
| Geometry | Crop, rotation, horizontal and vertical flips, straightening, and crop aspect |

A full paste uses every group. A scoped paste changes only the selected groups and keeps the
destination photo's other values. When several photos are selected, paste applies to the entire
selection and development continues through a bounded worker queue.

User presets save the same complete develop state and geometry. Older presets or paste scopes that
do not contain a Geometry field are read with Geometry included for compatibility.

## Without a scanner plug-in

If no scanner plug-in is installed at startup, the shared Library and Develop sidebar does not
automatically show the missing-plug-in explanation, rescan control, or simulator block. Image
import remains available.

Scanner rescan and simulator support have not been removed. They remain available through the
scanner entry point and Settings, and the existing scanner UI appears when a plug-in is installed
or the simulator is explicitly enabled.

## Print layouts and output counts

Print has seven layouts: single image, contact sheet, picture package, custom package, cyanotype,
glass plate, and gelatin silver. Cyanotype, glass plate, and gelatin silver reuse the single-image
controls. With several photos selected, the four individual-image layouts show one full print page
after another in a vertical scroll.

Export and Quick Export count finished pages, not selected source photos. For example, 39 photos
in a 6 × 7 contact sheet become one composed file; a four-up picture package becomes 10 pages; the
default custom package becomes one page; and the four individual-image layouts become 39 files in
a bounded batch.

Package preview reuses an existing thumbnail, developed image, or raw preview and creates only a
small fast preview when none exists. Final export calculates each placement from source metadata,
develops only the pixels required by that placement, prepares two to four sources concurrently,
and keeps the Core Image graph connected until the final page render. A shared render context and
a 512 MiB per-page source-raster budget prevent one page from expanding into an unbounded set of
full-resolution intermediate images.

## Print profiles

The ICC controls in Print have different jobs.

| Setting | On-screen preview | Print Export | Develop preview |
|---|---|---|---|
| Printer output profile | Shows the print result | Applied to the completed page | Never applied |
| C-print proof profile | Soft-proofs the lab and paper process | Not baked into the delivery file | Never applied |
| General soft proof | Used in its configured display scope | Display aid only | Follows its own setting |

A printer output profile is not applied to one source before that source is duplicated. The
contact sheet, picture package, or custom package is composed first, then the profile is applied
once to the whole page. Repeated placements of one source and mixed-source layouts therefore
receive the same output conversion.

The C-print proof profile is the lab-supplied process preview. It is never silently substituted as
the output profile. See [Print layouts and C-print preview](../reference/C_PRINT.md) for profile
requirements and the accuracy boundary.

## What changes the source

| Action | Source in Finder | Catalog and edits |
|---|---|---|
| Folder `×` | Kept | Folder and photos removed from the library |
| Drag to another folder | Moved; a new name is chosen on collision | Relinked to the new location |
| Move or rename in Finder | User's change is kept | Automatically relinked through the bookmark |
| Apply folder development | Kept | Process and target updated, then rerendered |
| Preset or copy/paste | Kept | Selected develop and geometry values updated |
| Print Export | Kept | A separate output file and render record are created |

## Large-library check

Above 256 photos, the filmstrip stops making long automatic scroll jumps after every selection
change. Visible cards and folder rows are created lazily.

The 2,000-frame stress check imports 24 MP, 40 MP, 60 MP, 3200 DPI, and 4800 DPI pixel fixtures
across 50 folders. It mixes every process and target, keeps color negative above half of the set,
applies crop and orientation changes, then verifies development, thumbnails, and the catalog
round-trip.

```bash
bash scripts/performance/run-virtual-library-stress.sh
```

The stress check is opt-in and is skipped by normal `swift test` runs.
