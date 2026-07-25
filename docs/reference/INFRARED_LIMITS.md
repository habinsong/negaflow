# Film GrainMend IR should avoid

[Docs home](../README.md)

Infrared cleaning reads the visible image and the infrared image separately, then overlays them
to find defects. It does not fit every film.

- Normal color film and dye-based black and white film can use IR.
- Ordinary black and white film keeps its silver, which blocks IR and can produce a wrong defect map.
- Kodachrome attenuates IR differently from other color film, so it can end up under- or over-corrected.

Evidence:

- [Epson technical notes and limits](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson film type table](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast on black and white and Kodachrome](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> If the film material cannot be confirmed, IR is not applied automatically. A wrong IR mask
> can erase real image structure as a defect.

## Where it applies automatically

`FilmType` only tells color from black and white and negative from positive. There is nothing
in it to separate dye-based black and white from silver, or a normal slide from Kodachrome.

| Film type | Automatic IR | Why |
|---|---|---|
| Color negative | Conditional | The plugin has to report IR and pass the alignment check |
| Color positive | Off | There is no way to know whether it is Kodachrome |
| Black and white negative and positive | Off | Dye-based and silver cannot be told apart |

This does not mean IR can never work on dye-based black and white or a normal color slide. The
current data cannot confirm the film material, so nothing is guessed.

## Alignment check

`InfraredDefectRemoval` compares the leakage texture in IR with the red channel of RGB and
looks for an integer offset. The result carries `AlignmentDiagnostics`.

| State | Meaning |
|---|---|
| `notRequested` | The caller said the two planes already match |
| `aligned` | Correlation passed the threshold and the best point is inside the search range |
| `insufficientTexture` | IR has too few alignment cues |
| `weakCorrelation` | Correlation did not pass the threshold |
| `searchLimitReached` | The best point sits on the search boundary |

The last three are not replaced with `(0,0)`. They stop with an `alignmentUnreliable` error. If
the best point lands on the search boundary, that counts as a failure whatever the offset size.

Automated tests do not stand in for RGB/IR alignment on a real device or for per-film results.
Real scanner checks follow the IR items in the
[real-device QA checklist](../validation/REAL_QA_CHECKLIST.md).

SANE device control and capture code live only in the separate `negaflow-scanner-sane`
repository.
