# Library to print workflow

[Docs home](../README.md)

This guide covers import, folder development, settings transfer, scanner thumbnails, and print output. A library folder follows the physical parent folder of each source.

> [!IMPORTANT]
> Source files stay unchanged unless you explicitly move a photo to another folder. Removing a folder from the library and deleting a file in Finder are separate actions.

## Import

Import shows a progress bar, percentage, completed count, and total count below the import controls. Metadata is read off the main thread, then the new frames are registered together so a large folder does not repeatedly rebuild the library index.

Automatic development of imported photos is **off by default**.

1. The source is registered.
2. Its original thumbnail and folder appear first.
3. Development starts when you apply a process and target to the folder or enter Develop.

To develop every import automatically, enable **Settings → Workflow → Develop imported images automatically**. The choice persists between launches.

Automatic import development applies only to frames registered by that import. It does not replace an existing developed state. Reprocessing developed photos happens only after an explicit folder **Apply** or settings paste.

Scanner captures are different. Their film type, process, and target are already chosen during the scan, so development starts after the scan result is published. Develop and Print filmstrips use a developed thumbnail for color negative, slide, black-and-white negative, and black-and-white positive sources. Library keeps the source thumbnail for source review.

## Folder list

- Collapsed and expanded states persist. Creating a folder or reopening the app does not expand the other folders.
- Every folder row has the same `×` control. It removes that folder and its photos from the **library only**; source files remain in Finder.
- The photo list inside a folder in Develop has its own height-limited scroll area. A long list or small window does not push the rest of the sidebar away.

### Moving photos to another folder

Drag one photo or a selection to another folder row to move the physical files and update the catalog together. The same rule applies to imported folders, app-created folders, and folders that contain scanner captures.

An existing destination name never causes an overwrite. If `frame.tiff` exists, negaflow tries `frame 2.tiff`, then `frame 3.tiff`, and so on. An IR companion of a scanner source moves in the same transaction.

### Finder changes

negaflow watches the registered physical source folders. After a short debounce, it rescans only the changed folder when it sees:

- A source file move or rename
- A registered folder move or rename
- A new image directly inside a registered folder

When the source's persistent bookmark resolves the new location, the existing frame is relinked. A moved folder keeps its folder ID and added date. A newly added file is imported without creating duplicates for files that are already known.

This is event-driven folder monitoring, not a periodic full-library scan. Frames with the same physical parent share one watch, and only folders that report a change are inspected.

## Development by folder

Choose a process and target beside the folder title, then select **Apply**. There is no separate on/off switch.

Apply rerenders every photo in the folder, including photos that were developed earlier. The new process and target are used while other user adjustments, such as exposure and contrast, remain. If a frame is already rendering, the folder job waits for that render to finish.

A progress bar, percentage, completed count, and total count appear beside Apply. Large batches keep only as many workers as there are render slots instead of starting one task per photo.

## Presets and copy/paste

Develop settings have seven independently selectable groups.

| Group | Values |
|---|---|
| Input Gamma | Source transfer interpretation |
| Base Scale | Film-base scale |
| Base | Film type and process, target, scanner profile, film base, channel-range calibration, Auto Balance, Auto Levels and neutral balance |
| Tone | Exposure, contrast, density, highlights, shadows, whites, blacks and tone curves |
| Color | Temperature, tint, color depth, vibrance, saturation, mixer, grading, calibration, B&W toning and film emulation |
| Detail | Grain, sharpness, halation, clarity, vignette, noise reduction, GrainMend strength and local adjustments |
| Geometry | Crop, rotation, horizontal and vertical flips, straightening and crop aspect |

A full paste or user preset replaces the destination's develop settings. A scoped paste replaces the selected groups' effective values and preserves the others. When only part of a look is pasted, its tone, color and texture contributions are folded into the values and the look reference is cleared. This keeps an old look from being added again. Pasting the same settings repeatedly gives the same state. Menus, shortcuts and the panel use the same paste scope.

Paste and user presets apply to every selected photo. One Undo or Redo covers the whole selection; Windows validates every destination before changing any. Thumbnails and the active preview refresh from the new recipe. Original files, ratings and source-bound defect edits are not copied.

User presets save the complete develop state and geometry. Older presets or paste scopes without Geometry include it for compatibility. A blank name gets the first free numbered name. Saving does not overwrite an existing preset just because its name matches.

## Without a scanner plug-in

If no scanner plug-in is installed at startup, the shared Library and Develop sidebar does not automatically show the missing-plug-in explanation, rescan control, or simulator block. Image import remains available.

Scanner rescan and simulator support have not been removed. They remain available through the scanner entry point and Settings, and the existing scanner UI appears when a plug-in is installed or the simulator is explicitly enabled.

## Print layouts and output counts

Print has eight layouts: single image, contact sheet, picture package, custom package, cyanotype, glass plate, gelatin silver and watermark. The five individual-image layouts show one finished page per selected photo in a vertical scroll. Watermark is its own layout; the other layouts keep their existing controls.

Export and Quick Export count finished pages. For example, 39 photos in a 6 × 7 contact sheet become one composed file; a four-up picture package becomes 10 pages; the default custom package becomes one page; and the five individual-image layouts become 39 files in a bounded batch.

Package preview reuses an existing thumbnail, developed image, or raw preview and creates only a small fast preview when none exists. Final export calculates each placement from source metadata, develops only the pixels required by that placement, prepares two to four sources concurrently, and keeps the Core Image graph connected until the final page render. A shared render context and a 512 MiB per-page source-raster budget prevent one page from expanding into an unbounded set of full-resolution intermediate images.

## Print watermark

Choose Watermark from the layout type menu, after Gelatin Silver. This adds a border below each photo without cropping it. You can add an equal-height border above. Photo paper size follows the photo plus its borders.

The bottom border shows the camera with the lens below it on the left. On the right it shows a logo, then focal length, aperture, shutter speed and ISO, with the date below. Turn on Logo to add one. With no file chosen, the negaflow logo is used. negaflow ships no maker logos: choose your own JPEG, PNG or other image file. Settings and templates store only the file path. Drawing checks the file and reuses the cached logo while its size and modification time are unchanged. If the file has been moved or deleted, only the logo is left out; the status dot at the bottom and the diagnostics report record it. Empty camera, lens, exposure and date fields stay empty. Only entered text is drawn. When the text is long or the border is narrow, as on a vertical photo, every item in the border is scaled down by the same amount. Text never runs past the photo or gets cut off.

The border can be white, black or a blur of the photo. On white the text is black with gray second lines. On black all text is white. On blur you choose black or white for the text and for the histogram. The histogram is drawn as columns of dots. The histogram and your name each go at the bottom center, or at the top left, center or right when the top border is on. The name position menu is always available: Bottom Center, Top Left, Top Center or Top Right. Choosing a top position turns on the top border. Name text is centered within its position. When the name and histogram share a position, the histogram sits above the name and each is centered. Blur and histogram reuse a valid filmstrip thumbnail when one is available. Otherwise they use a reduced photo image. Templates save the paper color and every watermark setting, including the text and the logo path.

## Print profiles

The ICC controls in Print have different jobs.

| Setting | On-screen preview | Print Export | Develop preview |
|---|---|---|---|
| Printer output profile | Shows the print result | Applied to the completed page | Never applied |
| C-print proof profile | Soft-proofs the lab and paper process | Not baked into the delivery file | Never applied |
| General soft proof | Used in its configured display scope | Display aid only | Follows its own setting |

A printer output profile is not applied to one source before that source is duplicated. The contact sheet, picture package, or custom package is composed first, then the profile is applied once to the whole page. Repeated placements of one source and mixed-source layouts therefore receive the same output conversion.

The C-print proof profile is the lab-supplied process preview. It is never silently substituted as the output profile. See [Print layouts and C-print preview](../reference/C_PRINT.md) for profile requirements and the accuracy boundary.

## DNG export

DNG writes the developed picture as an uncompressed 16-bit linear RGB file (`PhotometricInterpretation = LinearRaw`) in the output color space you pick: sRGB, Display P3 or Adobe RGB. Tone and color are already baked in, so other apps read it as an output-referred file. The file carries copyright, scanner, software, date and film notes under the same metadata policy as TIFF. Source camera EXIF, IPTC and GPS are not copied. It takes 6 bytes per pixel, so a 24-megapixel frame is about 144 MB.

DNG is offered for uncompressed sources: TIFF, camera RAW and DNG. JPEG, PNG and HEIC sources cannot be exported to DNG. Develop, the `PRINT` target and Print layouts all support DNG. Print DNG records the composed page in standard RGB with a ColorMatrix; printer ICC conversion is skipped. DNG export uses the folder selected in Export and keeps the `.dng` extension. Completion requires the final file to be published and checked. exiftool and Apple’s image decoder read the file. Rendering in Lightroom or Camera Raw has not been measured.

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

Above 256 photos, the filmstrip stops making long automatic scroll jumps after every selection change. Visible cards and folder rows are created lazily.

The 2,000-frame stress check imports 24 MP, 40 MP, 60 MP, 3200 DPI, and 4800 DPI pixel fixtures across 50 folders. It mixes every process and target, keeps color negative above half of the set, applies crop and orientation changes, then verifies development, thumbnails, and the catalog round-trip.

```bash
bash scripts/performance/run-virtual-library-stress.sh
```

The stress check is opt-in and is skipped by normal `swift test` runs.
