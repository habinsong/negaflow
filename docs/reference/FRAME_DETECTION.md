# How flatbed frame detection finds film

[Docs home](../README.md)

A flatbed preview shows a holder, the light that gets past it and the loaded film. Before a full scan is worth starting, automatic frame detection decides which parts are film and where one frame ends and the next begins. It knows the real size of the previewed area in millimetres, so it converts a film format to pixels exactly.

## Film is found by texture

Brightness cannot tell film from an empty holder window. Measured on an Epson GT-X900 preview:

| What the column contains | Mean brightness |
|---|---|
| Empty holder window, lamp passing straight through | 0.92 |
| Film in the next window | 0.10 |
| Holder mask | 0.002 |
| Third-party holder with a white background | 1.00 |

Sorting by brightness picks the empty windows and discards the film, and a white holder background inverts the order. Texture separates them, because grain and a picture exist only on film:

| What the column contains | Vertical detail |
|---|---|
| Film | 0.0044 – 0.032 |
| Holder mask, empty window, white background | 0.00005 – 0.001 |

The gap is an order of magnitude and keeps its sign across film type, holder and polarity. Every stage below uses it.

## Stages

1. Column texture. Detail is measured down each column of the preview. Columns with grain and picture become slot candidates.
2. Slots. Candidate columns grow out to the film edge and are matched against the width of the selected format. A slot that touches the edge of the scanned area is dropped, because the scan area cut that window in half and the full scan would capture the wrong region.
3. Bands. Inside a slot, the rows with film are separated from the holder above and below. A row is film when it differs from the holder beside it or carries texture. Brightness alone loses the dense frames of a slide, and texture alone loses the gaps and flat frames.
4. Grid. A comb of gap positions is fitted over the (pitch, phase) plane. The score is the contrast between what sits inside a cut and what sits in the gap, so the fit does not depend on whether the gap is clear base, maximum density or a holder rib.
5. Refinement. Each boundary snaps to the nearest gap, then the whole set is re-fitted to an even spacing, since frames on a strip are evenly spaced. Scanning the same strip twice lands within 0.2 mm.

## What it refuses

| Situation | Result |
|---|---|
| Holder with no film | Nothing. The windows have no texture, so no slot forms |
| Holder with one strip in three windows | Only the loaded window |
| Window cut in half by the scan area | Dropped |
| A cut that falls off the end of the film | Dropped. Interior cuts are kept even when unexposed |
| A strip with no periodic gap evidence | Nothing |

## Formats

The along-strip length is the frame pitch direction and the across-strip length is the slot width. Both come from the selected format, so half frame and 645 get their axes the right way round.

| Format | Along strip | Across strip |
|---|---|---|
| 35 mm full frame | 36 mm | 24 mm |
| 35 mm square | 24 mm | 24 mm |
| 35 mm half frame | 18 mm | 24 mm |
| 120 · 6×4.5 | 41.5 mm | 56 mm |
| 120 · 6×6 – 6×17 | 56 – 168 mm | 55 – 56 mm |

The 35 mm pitch is set by perforation transport and barely moves, so the search is narrow. A 120 camera sets its own spacing, so the search is wider. Neither is pinned to a fixed number.

## Measurements

Ten real Epson GT-X900 previews, 1768 × 2906 at 300 dpi over a 149.86 × 246.38 mm area.

| Preview | Holder | Result |
|---|---|---|
| Black and white negative, three strips | Genuine | 3 slots × 6 cuts |
| Black and white negative, one strip loaded | Genuine | 1 slot × 6 cuts, the two empty windows ignored |
| Color negative, three strips | Genuine | 3 slots × 6 cuts |
| Color negative, one strip loaded | Genuine | 1 slot × 6 cuts |
| Color slide, three strips | Genuine | 3 slots × 6 cuts |
| Color slide, one strip loaded | Genuine | 1 slot × 6 cuts |
| Color negative, gaps covered by the holder | Third-party | 1 slot × 5 cuts |
| Color negative, holder wider than the scan area | Third-party | 2 whole windows; the two half windows dropped |

Fitted pitch across every strip: 37.65 – 38.12 mm. Detection takes 0.5 – 0.9 s per preview in a debug build.

> [!NOTE]
> These measurements are 35 mm only. The 120 formats are covered by synthetic fixtures, so their spacing search has not been checked against a real 120 preview.

## Where the code lives

| File | Role |
|---|---|
| `FlatbedFrameGridDetector.swift` | Entry point, format geometry, frame extents |
| `FlatbedFrameGridDetector+Profiles.swift` | Column and row profiles, texture, common statistics |
| `FlatbedFrameGridDetector+Slots.swift` | Slots, film presence, bands |
| `FlatbedFrameGridDetector+Grid.swift` | Gap evidence, comb fit, boundary refinement |

`FlatbedFrameDetector` remains as the fallback for a preview whose physical size is unknown.
