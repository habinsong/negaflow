# GrainMend

[Docs home](../README.md)

GrainMend repairs dust, pinholes, scratches and emulsion damage on film. Nothing is written into the original. The result is kept as an ordered edit history.

| Tool | Where it looks | How it repairs |
|---|---|---|
| Automatic | The whole photograph | Conservative, only defects it is confident about |
| Guided | An area you choose | Looks closely, down to small specks and faint defects |
| Brush | The spot you paint | Carries surrounding structure and texture across |
| Clone stamp | A source point you choose | Copies real source pixels at a fixed offset |
| IR | The scanner's infrared channel | Divides out partial attenuation directly (`raw ÷ (1 − attenuation)`, up to 2× gain); opaque cores (`>= 50%`) go to the RGB patch repairer |

The develop screen has automatic, guided, brush and clone stamp. IR can be turned on at the scan step when the plugin reports the capability, and once the scan is done its result joins the same GrainMend layer list.

> [!CAUTION]
> GrainMend RGB works differently from hardware IR cleaning. GrainMend IR is not an implementation of, or a compatibility mode for, Digital ICE, iSRD or SRDx.

## The hard parts

Film defects and the structure of the photograph sit in the same pixels.

- Dust shows up as small, irregular bright or dark blotches.
- A pinhole can look like an isolated, strong dot.
- Scratches are long and thin, but so are wires, window frames and lettering.
- Emulsion damage changes color and texture together.
- At high resolution, film grain is the same size as a small defect.

Wiping out high frequency as a whole takes grain and edges along with the dust. GrainMend splits the work into detection, classification, repair and storage.

## Order of work

The detection mask and the repaired result are kept apart, which is what lets you inspect the mask, apply only some of the defects, or rebuild the repair. The steps:

1. Input image, inspection area and size.
2. Defect candidates, then mask cleanup.
3. Defect classification.
4. Structure check: if it is structure in the photo, it is not applied.
5. Find a source patch nearby.
6. Match brightness, texture and direction.
7. Blend the boundary.
8. Add to the edit history.

## Tools

### Automatic

Across the whole photograph, it finds only defects it is confident about. Missing a small defect is preferred over wrongly erasing a large structure. It never slips into the default develop, and you have to run it before anything is added.

### Guided

You pick a rectangle, and only that area and its surroundings are analyzed. Since you have already pointed at the defect, it goes after small specks, faint defects and dense clusters more aggressively than automatic does.

It reads wider than the result it produces, so the surrounding pixels used for the repair are not cut off at the edge of the area. The current maximum context radius is 264 pixels.

### Brush

You paint the spot to repair yourself. It does not cover what you painted with a color. It finds a matching source patch near the mask and carries the structure and texture across. When no patch matches, it can fall back to the detection path in a limited way.

### Clone stamp

`⌥`-click on Mac (`Alt`-click on Windows) picks the source point, then you draw on the target. It uses no automatic detection. It holds the offset between the two points and copies the real pixels.

The edit history keeps diameter, hardness, coordinates and offset, and it still applies to the same original coordinates after a rotation, a flip or a crop. Offsets snap to whole pixels, and nothing outside the image is applied.

### IR

Used only when the plugin hands over a real IR channel and the size and area line up with the RGB. For partially occluded pixels, GrainMend IR divides out optical attenuation directly (`raw ÷ (1 − attenuation)`, capped at 2× gain) so underlying detail and grain stay intact. Only heavily occluded opaque cores (`>= 50%` attenuation) go to the RGB patch repairer.

## Finding defects in RGB

### Difference from the surroundings

Brightness differs from photograph to photograph, so there is no single global threshold. It compares each pixel with surrounding pixels, checks how much brightness varies nearby and follows the local angle to find bright dust and dark defect candidates.

### Mask cleanup

Isolated noise is dropped, broken defects are joined, and pixels touching in any of 8 directions become one blob. A large area can be split into tiles, but a blob that straddles a boundary is merged again in whole-image coordinates.

### Resolution differences

The same speck of dust is a different number of pixels at 1200 dpi and at 7200 dpi. When resolution information can be trusted, the limits follow real size. Without it, the scanner model is not guessed and a conservative pixel-based rule is used.

### Classification

Each blob is measured for:

- Area and bounding box
- Ratio of the long axis to the short axis
- Horizontal, vertical and diagonal angle
- How straight and dense the mark is, plus its contrast against surrounding pixels
- Whether it continues into a nearby edge
- Its relationship with other blobs

The result is split into dust, pinhole, scratches by direction, emulsion damage and micro specks, each with a confidence.

### Not erasing lines that belong to the photo

Wires, railings, building corners, window frames and lettering must not be read as scratches. Parallel lines, grids, continuity of edges and lines attached to scene structure get their own check. Automatic rejects false positives more strictly, and guided also accounts for your choice of location.

## Repair

1. Find a source patch near the defect that does not overlap the mask and whose structure matches.
2. Match the low-frequency brightness and color difference between the patch and the target.
3. Keep the patch's high-frequency texture so film grain carries across.
4. For a long scratch, look first at the direction that continues from both ends.
5. At the mask edge, blend the original and the repaired patch smoothly.

Strength is the blend ratio between the finished patch and the original.

Sometimes an automatic repair cannot know what was underneath. If there is no usable surrounding texture, or the defect covered a whole important structure, it needs the brush, the clone stamp or separate precise work.

## IR handling

### Input conditions

- The plugin explicitly reports the IR capability.
- RGB and IR belong to the same scan session.
- Both images have the same pixel size and the same expected area.
- The files can be read and pass the original ID check.

Even when a model name is known to have IR, it is not used on screen or in a request unless the plugin reports it.

### Alignment

Optics and sensor readout can leave RGB and IR a few pixels apart. Global alignment first matches IR defect points against local darkness in the red channel, and falls back to IR leakage texture correlation when needed. The peak confidence and whether it landed at the edge of the search range are both recorded.

That global offset is an advisory starting seed rather than a hard failure gate. When global alignment has low confidence or hits the search limit, detection starts from `(0, 0)`, votes a coarse consensus offset from strong candidates, and aligns and confirms each defect individually against the visible red channel (`>= 4σ`). Any candidate that cannot be confirmed against the red channel is discarded.

### Subtracting the scene pattern

Film dye and density can show through into IR. GrainMend IR separates defects from the scene in four steps:

1. Flood-fill and exclude dark film-holder and rebate regions connected to the image border first.
2. Build a local morphological grayscale closing baseline (`localBaseline`). Narrow defects are bridged over, while broad cyan-dye scene ghosting stays inside the baseline.
3. Convert IR values to optical density `log(baseline / value)`.
4. Estimate the clean-film floor and `σ` from the scan's median and interquartile range (IQR), gather candidates whose area-scaled significance meets `Σ(density − floor) ≥ mσ·√area`, confirm each locally against the visible red channel (`>= 4σ`), and expand confirmed masks via hysteresis.

### Safety conditions

- An abnormally wide mask is not applied.
- Any candidate that cannot be locally aligned and confirmed against the visible red channel (`>= 4σ`) is discarded.
- Automatic IR is enabled for dye-image color films (both color negative and color slide/positive) and blocked for silver-image black-and-white films.
- Kodachrome and special emulsions cannot be detected from `FilmType` alone, so disable IR manually when needed.

Commercial IR tools place their own limits on ordinary black and white and on Kodachrome:

- [SilverFast: iSRD dust and scratch removal](https://www.silverfast.com/about-silverfast-why-scanning-basics-of-scanning/why-silverfast/silverfast-feature-highlights/isrd-dust-scratches-removal-eliminate-defects-with-infrared-channel/)

GrainMend IR is not a copy of, or a compatibility mode for, those commercial tools. Per-film IR limits and the conditions where alignment fails are in [Film GrainMend IR should avoid](../reference/INFRARED_LIMITS.md).

## Edit history and storage

Automatic and guided repairs, brush and clone stamp edits, and IR share one ordered edit list.

What each entry carries:

- ID and kind
- Order of application
- Whether it is on, and its strength
- Area, mask, clone source offset
- Defect classification and diagnostic values
- Original frame and edit version
- The repaired patch, or the values needed to rebuild it

An earlier repair changes the input to a later one, so the order of the list is part of the edit history too.

The original is not modified. GrainMend history is stored in a sidecar the app manages. Original SHA-256, edit version and a history fingerprint tie the input together. If the sidecar is missing or broken, the cache is not treated as an original.

The GrainMend cache is a derived file, there for fast display and re-rendering. If it is missing or fails its check, it is rebuilt from the original and the edit history. If the result an export needs cannot be produced, the export fails instead of substituting the original.

## Performance

- A small edit recomputes only the defect and its surrounding context.
- A large area is split into overlapping tiles with margin for the boundary.
- Results are collected only from the non-overlapping centers of the tiles.
- At most 4 tiles are processed at once.
- `CleanedRawCanvas` copies only the rectangle that changed.
- Copies for undo share storage until something actually changes.
- Under memory pressure, rebuildable images and the patch cache are dropped.

Real times depend on resolution, defect count, area size and hardware.

Measured 2026-07-25 on a macOS Release build (Mac14,3 arm64 with 24 GiB of memory on macOS 26.5):

| Path | Input | Result |
|---|---|---:|
| Guided detection | 1600×1600, 25 specks of dust | 0.35 s, 25 detected |
| Partial ROI detection | 1600×1600 | 0.38 s |
| Guided dense stress | 1280×960, 8 images × 3 runs | median 0.423 s, p95 0.488 s, max 0.526 s |
| IR detection (before August 2026 rewrite) | 6000×4000, 24MP | 1.042 s, peak memory growth 249.2 MiB |

The IR detection row above was measured before the August 2026 closing-baseline and attenuation-recovery rewrite. Across 24 dense stress runs, the lowest mask coverage at defect sites was 99.80% and the highest mean residual error was 2.70/255. These are macOS regression measurements on synthetic input; Windows runs the matching GrainMend RGB and IR pipeline in C++ (`negaflow-windows/src/Native/imaging/`). None of these numbers promise processing times on another machine or on real film.

## Benchmark

`defect-bench` can produce these files and values:

- before and after images, diff and mask
- 100% crops
- Detection count and confidence
- Processing time
- PSNR and absolute error when reference images exist

```bash
swift run -c release negaflow defect-bench <input-dir> \
  --reference-dir <reference-dir> \
  --out <report-dir>
```

RGB regression uses the 44 damaged and expert-restored pairs from FILM-R v2:

- Dataset: Authentically damaged & manually restored film scans (FILM-R v2)
- Author: Daniela Ivanova
- DOI: <https://doi.org/10.6084/m9.figshare.21803304.v2>
- License: CC BY 4.0 (<https://creativecommons.org/licenses/by/4.0/>)
- Pairs: 44
- Total size: 437,570,872 bytes

The automatic path applies sensitivity 0.7 and an over-detection safety line. On the 44 FILM-R pairs, 34 images improved and 6 got worse. The mean PSNR change is +0.466 dB, the worst case is −1.338 dB, and weighted worsened pixels are 0.017%.

When automatic meets a high density of candidates it stops applying and points you at guided. That safety line does not apply to guided, where you set the range, nor to the brush, the clone stamp or IR. 6 images still have lower PSNR than the expert restoration. None of this proves every photograph improves, that RGB and IR are equivalent, or anything about IR quality on a real scanner.

## Test coverage

- 8-direction connectivity and masks
- Morphological operations
- Dust, scratch and micro speck detection
- Rejecting lines and grids as false positives
- Tile boundaries in a large area
- Scratch repair by direction
- Matching surrounding texture and brightness
- Brush masks
- Clone stamp offset, brush edge softness and patch blending
- IR alignment, anchors, blobs and memory limits
- Applying at the original stage and rendering the app's edit history
- Adding repeatedly, and undo
- Frame ownership while moving around the screen

Some performance tests run only when an environment variable is set. The presence of a test file is not a claim that it ran in every environment.

## Names and trademarks

`GrainMend` is negaflow's own feature name.

- `Digital ICE` may be a trademark of Eastman Kodak Company or a related rights holder.
- `iSRD`, `SRDx` and `SilverFast` are trademarks of LaserSoft Imaging.
- These names are used only for technical comparison and product identification.
- GrainMend is not affiliated with third-party tools and does not claim to be compatible or equivalent with them.

## Where the code is

- `negaflow-mac/Sources/Chromabase/DefectRemoval/`
- `negaflow-mac/Sources/negaflowApp/Features/Defects/`
- `negaflow-mac/Sources/negaflowApp/Features/Develop/Inspector/Tools/DefectControlsSection.swift`
- `negaflow-mac/Sources/negaflowCLI/Commands/CLI+DefectBenchCommand.swift`
- `negaflow-mac/Tests/ChromabaseTests/Defect*.swift`
- `negaflow-mac/Tests/negaflowAppTests/Defect*.swift`
- `negaflow-mac/Config/defect-corpus-film-r-v2.json`
- `negaflow-mac/scripts/defect-corpus/`
- `negaflow-windows/src/Native/imaging/defect_*.cpp`
- `negaflow-windows/src/Native/imaging/infrared_*.cpp`
