# Film GrainMend IR should avoid

[Docs home](../README.md)

Infrared cleaning reads the visible image and the infrared image separately, then overlays them to find defects. It does not fit every film.

- Normal color film and dye-based black and white film can use IR.
- Ordinary black and white film keeps its silver, which blocks IR and can produce a wrong defect map.
- Kodachrome attenuates IR differently from other color film, so it can end up under- or over-corrected.

Evidence:

- [Epson technical notes and limits](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson film type table](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast on black and white and Kodachrome](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> If the film material cannot be confirmed, IR is not applied automatically. A wrong IR mask can erase real image structure as a defect.

## Where it applies automatically

What decides this is what forms the image, not whether the film is negative or positive. Colour film bleaches its silver away during processing and keeps only dye, and dye is transparent to infrared. Black and white film is a silver image and blocks infrared, so the correction would read the photograph itself as one large defect and erase it.

| Film type | Automatic IR | Why |
|---|---|---|
| Color negative | Conditional | Dye image. The plugin has to report IR and pass the alignment check |
| Color positive | Conditional | Dye image. Same conditions as colour negative |
| Black and white negative and positive | Off | Silver image blocks infrared |

`FilmType` cannot separate dye-based black and white from silver, and it cannot tell Kodachrome from a normal slide, so two cases are left to the user.

- Dye-based black and white is scanned as black and white, so IR stays off even though the film would allow it. Nothing is guessed from the film type alone.
- Kodachrome is a colour slide, so IR is offered. Its dyes attenuate infrared differently from E-6, which can leave a defect under- or over-corrected. Turn the layer off if the result looks wrong.

## Alignment check

`InfraredDefectRemoval` compares the leakage texture in IR with the red channel of RGB and looks for an integer offset. The result carries `AlignmentDiagnostics`.

| State | Meaning |
|---|---|
| `notRequested` | The caller said the two planes already match |
| `aligned` | Correlation passed the threshold and the best point is inside the search range |
| `insufficientTexture` | IR has too few alignment cues |
| `weakCorrelation` | Correlation did not pass the threshold |
| `searchLimitReached` | The best point sits on the search boundary |

The last three are not replaced with `(0,0)`. They stop with an `alignmentUnreliable` error. If the best point lands on the search boundary, that counts as a failure whatever the offset size.

Automated tests do not stand in for RGB/IR alignment on a real device or for per-film results. Checks on a real scanner are done by hand, on real film.

SANE device control and capture code live only in the separate `negaflow-scanner-sane` repository.
