# Fixed negative response

[Docs home](../README.md)

## MAIN/PRINT and composed targets

`fixed-density-linear-v6` applies to negative `MAIN/PRINT` without a scanner profile. It uses a fixed density calibration. Changing the other pixels, crop or frame histogram does not change the inversion of a given transmittance with the same base and settings. No scene vibrance is applied.

Custom targets and EXPIRED use the same fixed inversion as MAIN. Custom color is applied after calibration. EXPIRED applies a correction only when its evidence gate passes; without eligible evidence its output matches MAIN. A stale scanner profile is ignored for these targets. Preview measurement caches include the target and scanner profile. MAIN comparison previews keep separate measurements so switching targets or opening the comparison cannot alter the selected render or its export.

`B` is measured film-base transmittance. `f` is 1 for the generic response, or the selected stock's fixed relative range factor. `0.62` is the generic film-gamma reference and `0.60D` is its gray-density reference. These are design assumptions, not measured values for every stock or scanner. Manufacturer Status M densities do not directly characterize scanner RGB.

```math
D_c = \log_{10}(B_c / \max(T_c,10^{-5}))
```

```math
q_c = D_c/f_c,\quad k=0.045,\quad d_t=0.60+0.62\log_{10}(k/0.18),\quad p=d_t\ln(10)/0.62
```

```math
E_c=\begin{cases}
k\,\operatorname{sgn}(q_c)(|q_c|/d_t)^p,&q_c<d_t\\
0.18\times10^{(q_c-0.60)/0.62},&q_c\ge d_t
\end{cases}
```

The film-density toe joins the straight log-exposure section with matching value and slope. Unexposed base produces zero scene exposure before WB. This power toe is a generic design, not a measured stock curve. Near-base inversion can amplify density noise.

Automatic controls remain opt-in. With Auto Color enabled, bare film base is excluded from neutral-axis samples before the output toe; strong scene casts may still require manual WB.

## Output curve

Channel WB and exposure act on scene-linear `E`. The same fixed output curve runs on each channel after WB. The middle `0.045...0.70` is identity and preserves RGB ratios. The shoulder changes highlight color ratios. Below `0.045`, a small black floor is added: `b=0.001` for color and `0.0005` for B&W. Above `0.70`, the rational shoulder approaches 1. Both joins have slope 1. Film-toe inversion and output black rendering are separate stages.

```math
F(x)=x+b(1-x/0.045)^2\quad(0<x<0.045),\qquad F(x)=b\quad(x\le0)
```

Auto Levels maps its output targets back through the inverse output curve before stretching: output black `0.003`, white `0.95`. Auto Color excludes channels at or below scene-linear `0.004`; unexposed base is zero and is excluded without a special border threshold. Non-adaptive targets keep fixed input-gamma reference units. For scene-linear negatives, the minimum usable span is 4% of the measured white rather than a fixed 0.04 exposure value.

The inverse film stage has no `1.8D` cap. The `1e-5` transmission floor protects the logarithm. RGB gamut mapping belongs to the output boundary. Each channel is bounded by the black floor and 1 at this stage. Later user adjustments may extend that range.

## Other targets

Explicit scanner targets retain scene analysis and the legacy `shoulder-print-response-v4`. Its fixed primitive remains available for compatibility. Scene analysis has no universal 1.8D cap. A stock preset uses fixed relative factors; it does not silently normalize each frame.

Film RAW decoding disables decoder output tone where the API supports it. macOS disables global/local tone, shadow bias and gamut mapping for scene-linear input. Windows film RAW uses LibRaw with linear transfer; digital-photo rendering stays separate. This does not provide a measured sensor-to-film characterization or guarantee matrix-free RAW output.

## Validation and sources

Tests use an independent straight-line forward film model, the same patch in different backgrounds, WB across a neutral wedge, and dense highlights. Synthetic regressions do not establish real-film color accuracy. Existing recipes render with the corrected algorithm; stored parameters and source files are retained. The macOS renderer identifier and thumbnail suffix distinguish the new rendering.

The equations were implemented in this repository. No darktable, RawTherapee or NegPy implementation was copied.

## Measured synthetic comparison

The regression reconstructs the original default from the retained v4 primitive, including its 1.8D range cap and automatic vibrance. It compares the same density patch `(0.48, 0.68, 0.70)` in four backgrounds with one fixed base. This is not the Reddit 18-frame test. A separate idealized forward film with a smooth toe supplies the tone and WB tests; it does not establish real-film accuracy.

| Metric | Original | First correction (v5) | Reviewed (v6) |
|---|---:|---:|---:|
| Frame-to-frame L* span | 40.49 | 0 | 0 |
| Frame-to-frame b* span | 35.22 | 0 | 0 |
| Local contrast at −3 EV | 1.57 | 2.17 | 0.97 |
| Maximum neutral-wedge C* after WB | 8.89 | 0.99 | <0.001 |

The v5 and v6 comparison uses the same forward toe model. Shadow local contrast near 1 means one input stop remains about one output stop. L* and C* use D50 Lab. The fixed-base patch remains tinted; consistency does not mean an arbitrary density is neutral. Run `FixedNegativeResponseTests` with `NEGAFLOW_RESPONSE_COMPARISON` set to an output JSON path to retain the measurements.

## Bundled roll check

The 18 detected frames in `Roll_Perforation.tiff` were also compared. Both inversion methods use one corrected roll-base estimate held fixed. The identical density patch has an L* span of 21.48 before the change and <0.001 after it; the b* span falls from 30.94 to <0.001. The original blue 1.8D limit activates on 18/18 frames. This follows the reported test idea; it does not reproduce the commenter’s exact settings.

This check exposed a separate base-estimation bug. A mixed backlight boundary replaced the film measurement `(0.354, 0.109, 0.057)` with `(0.570, 0.510, 0.364)`. The rescue and envelope stages now reject a replacement that looks like the light on both mask-chroma axes. The output curve also acts on each channel after WB: an extreme blue value no longer drives the luminance mapping of the other channels. There is no measured color reference for this roll. These checks establish consistency and bounded output, not calibrated color accuracy. Set `NEGAFLOW_RESPONSE_ROLL_DIR` to an output folder and run `testBundledRollFrameConsistency` to save the images and JSON.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
