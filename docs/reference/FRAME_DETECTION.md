# How flatbed frame detection finds film

[Docs home](../README.md)

A flatbed preview shows a holder, the light that gets past it, and whatever film is loaded.
Automatic frame detection has to decide which parts of that picture are film, and where one frame
ends and the next begins, before the full scan is worth starting.

The detector knows the real size of the previewed area in millimetres, so it can convert a film
format into pixels exactly instead of guessing from proportions.

## Film is found by its texture, not by its brightness

Brightness cannot tell film from an empty holder window. Measured on an Epson GT-X900 preview:

| What the column contains | Mean brightness |
|---|---|
| Empty holder window, lamp passing straight through | 0.92 |
| Film in the next window | 0.10 |
| Holder mask | 0.002 |
| Third-party holder with a white background | 1.00 |

Sorting by brightness therefore picks the empty windows and discards the film, and a holder whose
background is white inverts the order outright.

Texture separates them without that ambiguity, because grain and a picture exist only on film:

| What the column contains | Vertical detail |
|---|---|
| Film | 0.0044 to 0.032 |
| Holder mask, empty window, white background | 0.00005 to 0.001 |

The gap is an order of magnitude and it does not change sign with the film type, the holder or the
polarity. Every stage below is built on it.

## Stages

1. **Column texture.** Detail is measured down each column of the preview. Columns that carry grain
   and picture become slot candidates.
2. **Slots.** Candidate columns are grown out to the edge of the film and matched against the width
   of the selected format. A slot that touches the edge of the scanned area is dropped, because it
   is a window the scan area cut in half and the full scan would capture the wrong region.
3. **Bands.** Inside a slot, the rows that hold film are separated from the holder above and below.
   A row counts as film when it differs from the holder beside it **or** carries texture; brightness
   alone loses the dense frames of a slide, texture alone loses the gaps and the flat frames.
4. **Grid.** A comb of gap positions is fitted over the whole (pitch, phase) plane. The score is the
   contrast between what sits inside a cut and what sits in the gap, so the fit does not depend on
   whether the gap is clear base, maximum density, or a holder rib covering it.
5. **Refinement.** Each boundary is snapped to the nearest gap and the whole set is then re-fitted to
   an even spacing, because the frames on a strip are evenly spaced. Scanning the same strip twice
   lands within 0.2 mm.

## What it refuses

| Situation | Result |
|---|---|
| Holder with no film | Nothing. The windows have no texture, so no slot forms |
| Holder with one strip in three windows | Only the loaded window |
| Window cut in half by the scan area | Dropped |
| A cut that falls off the end of the film | Dropped; interior cuts are kept even when unexposed |
| A strip with no periodic gap evidence | Nothing, rather than an arbitrary grid |

## Formats

The along-strip length is the frame pitch direction and the across-strip length is the slot width.
Both come from the selected format, so half frame and 645 are handled with their two axes the right
way round.

| Format | Along strip | Across strip |
|---|---|---|
| 35 mm full frame | 36 mm | 24 mm |
| 35 mm square | 24 mm | 24 mm |
| 35 mm half frame | 18 mm | 24 mm |
| 120 · 6×4.5 | 41.5 mm | 56 mm |
| 120 · 6×6 to 6×17 | 56 to 168 mm | 55 to 56 mm |

The 35 mm pitch is set by perforation transport and barely moves, so the search is narrow. A 120
camera sets its own spacing, so the search is opened up. Neither is pinned to a fixed number.

## What was measured

Ten real Epson GT-X900 previews, 1768 × 2906 at 300 dpi over a 149.86 × 246.38 mm area.

| Preview | Holder | Result |
|---|---|---|
| Black and white negative, three strips | Genuine | 3 slots × 6 cuts |
| Black and white negative, one strip loaded | Genuine | 1 slot × 6 cuts, the two empty windows ignored |
| Colour negative, three strips | Genuine | 3 slots × 6 cuts |
| Colour negative, one strip loaded | Genuine | 1 slot × 6 cuts |
| Colour slide, three strips | Genuine | 3 slots × 6 cuts |
| Colour slide, one strip loaded | Genuine | 1 slot × 6 cuts |
| Colour negative, gaps covered by the holder | Third-party | 1 slot × 5 cuts |
| Colour negative, holder wider than the scan area | Third-party | 2 whole windows; the two half windows dropped |

Fitted pitch across every strip: 37.65 to 38.12 mm. Detection takes 0.5 to 0.9 s per preview in a
debug build.

> [!NOTE]
> The measurement above is 35 mm only. The 120 formats are covered by synthetic fixtures, so their
> spacing search has not been checked against a real 120 preview yet.

## Where the code lives

| File | Role |
|---|---|
| `FlatbedFrameGridDetector.swift` | Entry point, format geometry, frame extents |
| `FlatbedFrameGridDetector+Profiles.swift` | Column and row profiles, texture, common statistics |
| `FlatbedFrameGridDetector+Slots.swift` | Slots, film presence, bands |
| `FlatbedFrameGridDetector+Grid.swift` | Gap evidence, comb fit, boundary refinement |

`FlatbedFrameDetector` remains as the fallback for a preview whose physical size is unknown.
