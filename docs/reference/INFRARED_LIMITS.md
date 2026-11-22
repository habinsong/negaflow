# Film GrainMend IR should avoid

[Docs home](../README.md)

Infrared cleaning reads the visible image and the infrared image separately and overlays them to find defects. It does not suit every film.

- Normal color film and dye-based black and white film can use IR.
- Ordinary black and white film keeps its silver, which blocks IR and can produce a wrong defect map.
- Kodachrome attenuates IR differently from other color film, so it can be under- or over-corrected.

Evidence:

- [Epson technical notes and limits](https://files.support.epson.com/pdf/pr48pr/pr48prps.pdf)
- [Epson film type table](https://files.support.epson.com/htmldocs/pr449p/pr449pug/projs_3.htm)
- [SilverFast on black and white and Kodachrome](https://www.silverfast.com/showdocu/en.html?direct=1&docu=1300)

> [!CAUTION]
> If the film material cannot be confirmed, IR is not applied automatically. A wrong IR mask can erase real image structure as a defect.

## Where it applies automatically

The deciding factor is what forms the image. Color film keeps only dye after processing, and dye is transparent to infrared. Black and white film is a silver image and blocks infrared, so the correction would read the photograph itself as one large defect and erase it.

| Film type | Automatic IR | Why |
|---|---|---|
| Color negative | Conditional | Dye image. The plugin must report IR and per-defect visible confirmation (`>= 4σ`) and coverage checks (`<= 5%`) must pass |
| Color positive | Conditional | Dye image. Same conditions as color negative |
| Black and white negative and positive | Off | Silver image blocks infrared |

`FilmType` cannot separate dye-based black and white from silver, or Kodachrome from a normal slide. Two cases are left to the user:

- Dye-based black and white is scanned as black and white, so IR stays off although the film would allow it. Nothing is guessed from the film type alone.
- Kodachrome is a color slide, so IR is offered. Its dyes attenuate infrared differently from E-6, which can leave a defect under- or over-corrected. Turn the layer off if the result looks wrong.

## Alignment check

`InfraredDefectRemoval` first matches IR defect points against local darkness in the red channel of RGB, falling back to high-pass IR leakage texture vs red-channel correlation when defect cues are scarce. The global result carries `AlignmentDiagnostics` and is a starting seed before each defect's offset is refined locally in the red channel.

| State | Meaning |
|---|---|
| `notRequested` | The caller said the two planes already match |
| `aligned` | Correlation passed the threshold and the best point is inside the search range |
| `insufficientTexture` | IR has too few alignment cues |
| `weakCorrelation` | Correlation did not pass the threshold |
| `searchLimitReached` | The best point sits on the search boundary |

When the global seed reports one of the last three states, detection does not stop immediately: it starts from `(0,0)`, votes a coarse consensus offset from strong IR candidates, and requires every candidate defect to pass local visible red-channel confirmation (`>= 4σ`) and the maximum coverage gate (`5%` default), stopping with `noDefects` or `coverageTooHigh` if those fail.

Automated tests do not replace checks of RGB/IR alignment on a real device or per film. Those checks are done by hand on real film.

SANE device control and capture code live only in the separate `negaflow-scanner-sane` repository.
