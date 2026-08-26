# GrainMend IR real scan measurement

[Docs home](../README.md)

How much of a defect GrainMend IR actually removes, measured on real scans rather than
synthetic fixtures.

| Item | Value |
|---|---|
| Material | Epson GT-X900, colour negative, 2400 dpi, 16 bit |
| Pairs | 5 (main scan and infrared pass) |
| Scored defects | 140 to 338 per frame |
| Measured | 2026-08-11 |

## How the score is made

The detector is not asked to grade itself. A defect counts only when the photograph
confirms it: the infrared candidate is matched to the darker mark in the red channel at its
own local offset, and it is kept only when that peak clears four sigma above the
surrounding noise. Removal is the log density excess at the defect centre against a ring
baseline, before and after correction. Overcorrection is the same number turned negative,
meaning the centre came out brighter than its surroundings.

## Acquisition comes first

The infrared pass must carry the same gamma table and focus as the main scan. Left at the
device default the film base clips at the white end, 9.07 per cent of the frame pinned at
65535, and the baseline that defect depth is measured against is gone. With both passes set
alike, clipping is zero. Measurements taken before that fix say nothing about the detector.

## Result

| Frame | Candidates to confirmed | Gain | Centre removal | Overcorrection mild/medium/severe |
|---|---|---|---|---|
| 19 | 483 to 262 | 1.12 | 90% | 5 / 0 / 0 |
| 20 | 726 to 407 | 1.84 | 85% | 16 / 8 / 3 |
| 21 | 1138 to 494 | 1.52 | 96% | 24 / 5 / 0 |
| 22 | 969 to 674 | 1.26 | 93% | 25 / 3 / 3 |
| 23 | 540 to 341 | 1.32 | 95% | 13 / 2 / 0 |

Gain is the measured ratio of visible density to infrared density. Occlusion is close to
flat across wavelength, so a value near one says the two passes agree about what was
covered. Mild means the centre came out 1 to 3 per cent brighter than its surroundings,
which is below film grain; severe means more than 6 per cent. Detection takes 0.6 to 0.9
seconds a frame and applying the correction another 0.1 to 0.3.

Between 96 and 99 per cent of the correction lands within eight pixels of a real infrared
defect, and average correction by red decile shows no trend, so the wider detection is not
leaking into the scene.

## By defect size

Wide dust used to survive while scratches came out clean. Four separate steps misread only
defects larger than a few pixels, and a fifth held every defect back by a constant amount.

| Narrow radius | Before | After |
|---|---|---|
| 1 to 2 px | 52 to 74% | 77 to 95% |
| 3 to 4 px | 77 to 89% | 93 to 99% |
| 5 to 7 px | 0 to 91% | 24 to 99% |
| 12 to 17 px | 0 to 73% | 58 to 89% |
| 18 px and up | 0% | 73 to 93% |

- The baseline structuring element grew from what the first pass observed, but that
  observation is made with the same baseline, so a defect wider than the element measures
  its own interior and looks small. It is sized from the resolution instead.
- The candidate threshold is one pixel's significance, so faint wide dust cleared no pixel
  at all. The same significance now applies to the area a defect covers.
- The null distribution came from the whole search plane, so a defect as large as the plane
  became its own null and halved the measured gain.
- The amount to restore was measured from the three sigma membership line rather than from
  the film's own floor, which left that offset behind on every defect.
- The upward bias of a peak selected for being large was a fixed one sigma. It is the
  inverse Mills ratio of the four sigma gate: full caution at the gate, nothing past eight.

## Not checked

- No visual pass over the corrected frames. Mild overcorrection is a number here, not a
  judgement about how it looks.
- No run of a full eighteen frame batch through the application.
- Frame 20 stays lower than the rest at 85 per cent. Its infrared density is around 60 per
  cent of the other frames, so the input itself is likely thin.
- One scanner only. V800, V850, and Coolscan have not been measured.
- Low resolution colour 16 bit scans come out black at 300 dpi and below. 2400 dpi is
  normal and no product effect is confirmed, but the cause is unknown.
