# Chroma Engine

[Docs home](../README.md)

Chroma Engine inverts and develops film. The code sits in the `Chromabase` module. The app and the CLI use the same module, so the same input goes through the same order of steps.

| At a glance | Detail |
|---|---|
| Default develop | `MAIN`, Auto Balance ON |
| Film base | Automatic measurement, eyedropper, direct RGB entry |
| Internal color | 32-bit floating point linear color space |
| Automatic features | Auto Balance ON |
| Output color space | sRGB, Display P3, Adobe RGB, custom RGB ICC |

> [!IMPORTANT]
> The default is `MAIN` with Auto Balance on. The switch is a small pill at the right of the Target heading. It appears only for color and B&W negatives on MAIN (including PRINT) and CS. It adjusts color and brightness from the current picture, and switching it off bypasses that step. Auto Tone, Auto White Balance, Auto Levels and Auto Color remain separate and off by default.

## What comes first

1. If the film base can be measured, the measurement wins over the default picked by name.
2. Film properties, scan light source, scanner style and scene auto-correction are kept apart.
3. Features like Auto Tone and Auto White Balance turn on only when you run them.
4. The same source, edit values and profile bundle go through the same order of steps.
5. Synthetic tests and real device validation are never presented as the same evidence.

## Order of steps

The working image is processed in a 32-bit floating point linear color space. Only operations that need gamma convert at their fixed step, and encoding for a screen or file format happens at the end.

1. Read the file and fix the orientation.
2. Linear input (camera RGB for RAW).
3. Film type: a positive goes to positive processing, a negative gets its base measured.
4. Optical density and inversion, then Auto Balance ON or OFF, then the RAW camera matrix.
5. Develop target and profiles.
6. Tone, color and local adjustment.
7. Detail and effects.
8. Display or output color space.

`CIContext` is not rebuilt for every render. It is reused, split by purpose: display, analysis and export. The preview computes only the size it needs and the latest edit version, and export renders again at source size.

Apple's Core Image documentation:

- [CIImage](https://developer.apple.com/documentation/coreimage/ciimage)
- [CIContext](https://developer.apple.com/documentation/coreimage/cicontext)
- [workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontext/workingcolorspace)
- [Core Image performance guide](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_performance/ci_performance.html)

## Film base

### Reason for measuring

The unexposed part of a negative is a reference point that combines film, development and the scan light source. The orange mask of color negative is in there too. Get the base wrong and every density and channel relationship after it goes wrong. Kodak's Portra 400 data also records minimum density, characteristic curves and dye spectral density separately:

- [Kodak Professional Portra 400 technical data](https://www.kodakprofessional.com/sites/default/files/wysiwyg/pro/resources/e4050_portra_400.pdf)

### Automatic measurement

`FilmBaseEstimator` evaluates the spatial distribution of bright pixels across the frame to identify the unexposed base.

- A film pixel cannot be brighter than the unexposed base.
- Anything much brighter may be backlight, perforation or outside the film.
- A real base tends to run in a wide band along the frame edge.
- With several film strips on one sheet, separated areas can be read together.
- A boundary where holder and film mix is trusted less than the interior.

It finds the brightness distribution on a downscaled analysis image, groups connected areas, then removes candidates that lie outside the film. When several strips pass the conditions, they are computed together. The result also records which method was chosen and how confident it is.

### Choosing the method

| Mode | Behavior |
|---|---|
| `Manual` | Uses the RGB you entered as Dmin. A successful eyedropper pick lands here too. |
| `Film` | Uses the measurement as Dmin, and the chosen film mainly supplies `dmaxNorm`. Film and light source defaults come in only when the measurement fails. |
| `Auto` | Uses spatial analysis, and falls back to the edge-based method on failure. |

Without a manual value, or with a wrong film ID, it moves to the next safe method. The brightest object in the scene is never taken straight as the film base.

## Optical density and inversion

Density comes from linear transmittance `T` and the per-channel base `Dmin`:

```math
D = \log_{10}\left(\frac{D_{\min}}{T}\right)
```

`D = 0` means the input equals the unexposed base. Perforation or backlight can go negative. Those values stay finite and are not clipped on the spot.

### Film type data

The current table holds 27 film names, covering color negative, black and white, and motion picture negative. The data is used for:

- The Dmin default when the base cannot be measured
- Fixed stock-relative density factors

Some values were approximated by reading curves in public material, and some were set conservatively. 27 names do not mean 27 validated color profiles, and once the base is measured, the measurement wins.

### MAIN/PRINT and CS

With Auto Balance ON, each channel uses its densest 0.2% scene percentile with a 1.8D range limit, followed by the `shoulder-print-response-v4` curve and muted-scene vibrance. OFF uses the same curve with a fixed nominal range (color 1.55D, B&W 2.17D). OFF also multiplies a scanner and film channel-range calibration for color negatives, taken from at least three frames of the same roll.

ON can change both brightness and color with scene content. Neither mode establishes measured film color accuracy. The formulas, the 1.8D limit and the RAW order are in:

[Negative response](../reference/PRINT_RESPONSE.md)

## Profiles come in three kinds

| Kind | The question it answers | Values |
|---|---|---|
| Film stock | What is the film's base and density range | Dmin/Dmax, film type |
| Light source | How did the scan light source affect each channel | Channel gain, base-driven correction |
| Scanner target | What tone and color style does the result have | Relative statistics from scans shot for this project |

Keeping these three apart avoids letting one film name stand for emulsion properties, light source color and a lab's output style at once. When a real base exists, the measurement wins over light source defaults. Scanner statistics are not used directly as an absolute color matrix for a scene.

The data is described in [film profiles](FILM_PROFILES.md).

## Develop targets

### `MAIN`

The default target, with Auto Balance on. The switch is described at the top of this page.

### `PRINT`

The working image matches `MAIN`. A valid RGB printer ICC is applied once, at the end of export. A missing or invalid profile fails instead of falling back to sRGB or some arbitrary paper values.

### `HS`, `SP`

A fixed rendering. It comes after white balance, exposure, the basic tone sliders and the parametric curve, and before the point curve, color mixer, color grading and calibration. A lab works the same way: the operator's density and color corrections go into the scan, and the print curve stays fixed. It reads nothing from the picture, so a pixel gives the same result in every photo. Per-frame exposure and color belong to the inversion and to the Auto Tone, Auto White Balance, Auto Levels and Auto Color buttons on the right. The neutral eyedropper reads the picture before the rendering, so the gray-axis tilt of `HS` stays after a pick.

The rendering is a luminance tone curve, a saturation gain that follows brightness, and for `HS` a small tilt of the gray axis. All curves are monotone cubic, so nothing bends at the knots.

- `SP` comes from four frames of one roll scanned on a real SP-3000 and on this project's own scanner, matched pixel by pixel. The tone curve takes a quarter of its weight from the percentiles of 185 SP-3000 frames. On those four frames the median CIEDE2000 to the SP-3000 scan falls from about 7.4 for `MAIN` to 3.9. One dark frame barely moves, because the lab removed a red shadow cast frame by frame there and a fixed rendering cannot.
- `HS` has no pixel pairs. It starts from `SP` and adds the median difference between the two machines on three rolls with matching film and roll names: slightly darker midtones, whites a little higher, colored pixels at 0.88× saturation, and grays leaning green in the bright half (a* about −1 to −4).
- `HS` sharpens the brightness channel. The radius is 0.9 px at the machine's 35 mm output (3089 px long edge) and scales with resolution, so preview and export match. The strength was not measured.

Picking a bundled profile still adds `scannerSignature`, the relative difference from rolls whose names and image counts match on both machines. Every profile today is `realOnly`.

- The relative difference is computed only when roll names and image counts match closely enough.
- Values whose direction flips are not applied.
- Color components are dropped for black and white.
- If the SHA-256 of any file or manifest is off, the whole profile bundle is refused.

### `F135`, `HR`

This project has no reference scans from a Pakon F-135 or a Kodak HR-500, so neither target is checked against its machine. Each has its own table, built from what labs and users report about that machine, and neither starts from the `SP` numbers. Both keep the gray axis neutral. Pakon users report yellow, green and blue tints, which points to scene balance that changed from frame to frame.

- `F135` (Kodak Pakon F-135, the consumer TLX/PSI scanner). Users say it is less saturated than a Noritsu, gets white balance right more often, keeps detail in highlights and shadows, and that some scans look flat; one user found its B&W output bright. Middle gray sits 0.3 stop brighter, like a consumer print. Midtone local contrast is 0.8–1.0, against 1.2–1.35 for `SP`. The toe is lifted (−6 stops at 0.101, `SP` 0.073) and the highlights roll off over a long range, so the scene white that the inversion places at linear 0.70 lands at sRGB 231. Saturation gain is 0.68–0.74, below `HS` everywhere.
- `HR` (Kodak Professional HR 500). A lab describes its output as close to a raw scan that you finish later, users say it handles color well, and its shadow detail is reported clean. Middle gray sits 0.1 stop dense and midtone local contrast is 1.15–1.2. Shadows run at 1.2–1.3, darker and cleaner than the linear shadows of `MAIN` (−6 stops at 0.018), and each shadow stop separates 1.6 times as much as in `SP`. Highlights do not fold as they do in `SP`; they climb at 1.2–1.35, and the scene white lands at sRGB 242. Saturation stays at 1.0 and drops to 0.88 in the highlights, where `SP` raises it.

Each rendering was applied to seven real negatives developed up to the stage where the targets start (two rolls, diagnostic use only). Averaged per photo, every pair among `MAIN` and the four targets differs by at least 2.9 CIEDE2000. The measured `SP`–`HS` pair differs by 4.3. Within single photos, high-key and midtone-heavy scenes bring `MAIN`–`HR` and `F135`–`HR` down to 2.0–2.6. Checking either target against its machine needs what `SP` had: the same negatives scanned on the real machine.

### `EXPIRED`

A recovery target for old film. It does not blanket-desaturate or stretch the range, and stays within limited correction that the current evidence supports.

### `CS`

`CS` (Custom) holds 18 color styles in three groups: Emulsion, Reversal, Dye Transfer, Skip Bleach, Plate Glass, Amber Glass, Ultramarine, Terracotta, Celadon, Nacre and Dichroic (11); Wetzlar, Classic, Studio and Rochester (4); Slide Show, Cinema and Point & Shoot (3).

A Custom target uses the `MAIN` inversion with Auto Balance and then applies the custom-3 tone, density and chroma response. Scanner profiles are not used with it. The CLI takes the same IDs, for example `--target classic`.

## The film look on a digital source

The left Film tab offers slide and color negative stocks. For a scan these are a color transform only, because the scan already carries the film's own latitude, density response, scatter and grain in its pixels.

A digital photograph carries none of that. Measurement showed what a color transform alone does there: on camera-rendered input the highlight steps collapsed to 0.0031, about one fourteenth of the same steps on flat input, while saturation still rose. The result reads as a digital filter.

So a source marked `Digital Color` or `Digital B&W` runs a separate chain that redoes what film does, in order:

1. Undo the camera's display rendering to estimate the exposure the film would receive. Clipped detail does not come back, so this is a plausible reconstruction.
2. Add scatter and halation while the image is still linear light, before any density exists. Returning light strikes the red layer first, producing a red-weighted glow, and redistributes light without adding energy.
3. Virtual development. A characteristic curve builds density, DIR couplers inhibit neighbouring layers, and a negative then goes through RA-4 paper. A negative's low gamma and the paper's high gamma are two separate curves, which lets highlights roll off without clipping.
4. The stock's color signature, since contrast already came from step 3.
5. Grain that follows density, and edge response from the datasheet MTF.

Scan sources never enter this chain. The switch is the source flag alone, and the scan path is unchanged.

Exposure is rescaled to the latitude of each emulsion. A reversal stock is white about a stop above mid grey, so pushing a six-stop digital scene into it unchanged leaves no highlight detail at all. The rescale preserves each stock's contrast ranking.

Grain and halation become film properties once a stock is selected, so the texture sliders set their strength instead of adding a second, separate effect.

## Develop controls

| Group | Items |
|---|---|
| Tone | Exposure, contrast, highlights, shadows, whites, blacks, RGB and per-channel point curves |
| Color | Temperature, tint, vibrance, saturation, 8-color HSL, three-zone color grading, channel correction, black and white conversion and toning |
| Detail and effects | Sharpness, clarity, dehaze, film grain, vignette, halation, noise reduction |
| Local adjustment | Radial, linear, polygon, brush masks, dodge and burn |

No combination of the basic tone sliders or the parametric curve reverses tones. Basic tone applies contrast, density, highlights, shadows, whites and blacks in that order, each on the result of the step before, and each step is monotone on its own. The four parametric curve sliders each move one knot placed at the 10, 35, 65 and 90% points of the photo's luminance, and a monotone cubic joins the knots. The knots sit at least 0.10 sRGB from each other and from black and white, so a slider pushed to its end moves its knot by at least 0.045 sRGB on any photo.

These values are stored as a step-by-step edit history. GrainMend and ordinary local adjustment differ in purpose and in how they are stored.

### Automatic corrections

| Control | Behavior |
|---|---|
| Auto Tone | Assigns exposure, contrast, density, highlights, shadows, whites and blacks. Exposure moves the scene's log-average luminance to a scene key: bright photos go down, dark ones go up, and a brighter scene gets a higher key. The other sliders are solved in the order basic tone applies them, each from the values the earlier steps leave. Pixels below diffuse white whose brightest channel newly reaches full scale are held to 0.5%; specular highlights and light sources brighter than diffuse white may clip. When a saturated color would clip, whites give way first, then exposure, then density and contrast lifts; density fills the midtones a held-back exposure leaves dark. Exposure and the measured scene key give way by at most one stop for this; if protecting the color would take more, the clipping is accepted. Keeps the user's color controls and curves. |
| Auto White Balance | Estimates temperature and tint from near-neutral luminance bands. Rejects samples with a clipped RGB channel and reduces correction when neutral evidence is sparse or covers a narrow tonal range. |
| Auto Levels | Measures common luminance endpoints and applies one luminance gain to RGB, so channel ratios stay. On negatives the endpoints go to the inversion's own black and white: linear 0.70 for color and 0.85 for B&W, the same white where the exposure shoulder starts. |
| Auto Color | Fits residual casts to neutral candidates. Uses channel slopes only when a fit predicts separate, unused luminance bands, and otherwise uses gains. Weak fallback evidence receives less correction. Channel slopes apply from the darkest evidence band up to white; darker tones keep the correction at the bottom edge of the evidence. |

Auto Tone checks the first proposal on a rendered preview. If it proposes a further exposure or white-point change, it renders that candidate too and accepts it only when a score of middle tone, endpoints, tonal range and clipping improves. A further brightening obeys the same channel limit. If the check, compared pixel by pixel with the neutral render, shows more than 0.5% of such pixels newly clipping, with the scanner target and curves included, Auto Tone lowers whites and then exposure, rendering up to three more previews to find the brightest setting inside the limit. When it picks between two renders, the one that clips less wins before the score is compared. This is a bounded correction, not a search for a unique ideal rendering. Repeating the command assigns settings rather than accumulating them, and resetting Auto Tone keeps the user's color controls.

Analysis uses area-weighted averages in linear RGB, with a bounded long edge. Tone and WB use an sRGB preview, so clipping means preview-channel clipping, not sensor saturation. These estimates cannot distinguish every subject color from an illuminant cast or establish measured film color accuracy. MAIN/CS Auto Balance and its muted-scene vibrance belong to the inversion stage.

## Color management

If the input carries a valid ICC, that color space is read. Internal math runs in the fixed linear working space, and the switch to an output space happens at display, soft proof and export.

Main supported outputs:

- sRGB
- Display P3
- Adobe RGB
- A user-selected RGB printer or output ICC

The printer profile's name, byte count and SHA-256 are pinned when export starts. If the file changes during the render, the run stops.

No claim is made that the current Core Image and ColorSync path produces bit-identical rendering intent and black-point compensation on every macOS version. That guarantee would need a separate ColorSync buffer path and memory checks for large 16-bit images first.

## Output encoding

Format settings sit outside the color pipeline, but they decide what survives in the delivered file.

JPEG stores color at a lower resolution than luminance unless the encoder is pushed past its subsampling threshold. Below that point chroma is halved both horizontally and vertically, which softens saturated edges while luminance detail stays intact. Quality at or above 95% is therefore encoded without chroma subsampling, and lower settings keep the value that was chosen because choosing them means asking for a smaller file. PNG and TIFF are lossless and never subsample. Their only quality control is bit depth, 8 or 16 bits per channel, and dithering is applied only at 8 bits, where it hides quantization banding.

## Performance and safety

- `CIContext` is reused per purpose.
- Adjustments use a lower-resolution preview, and export rebuilds from the source.
- Long-running tasks re-check the frame ID, edit version and session immediately before applying a result.
- When memory runs low, caches such as thumbnails and previews are dropped.
- Originals and edit history are kept apart from caches.

## Levels of validation

1. Formula tests: monotonicity of the curve, the anchors, the inverse
2. Synthetic images: known input and output, clipping, orientation, color space
3. Synthetic IT8: the mathematical round trip over 264 patches
4. Real shooting statistics: the `realOnly` profiles
5. REAL/TARGET pairs: a device quality gate with separate validation material
6. Real hardware: an actual scanner, film, display and print

A good synthetic IT8 result does not prove absolute accuracy on real negatives. Judging scanner profile quality follows [Scanner profile quality gate](../reference/PROFILE_QUALITY_GATE.md) and [IT8 color validation](../reference/IT8_COLOR_VALIDATION.md).

## Where the code lives

- `Sources/Chromabase/Engine/`
- `Sources/Chromabase/Film/`
- `Sources/Chromabase/Develop/`
- `Sources/Chromabase/Adjustments/`
- `Sources/Chromabase/Profiles/`
- `Sources/Chromabase/Imaging/`
- `Sources/Chromabase/Export/`

The current product version is `1.2.6`. Changes to the edit history and profile schemas will require validation in later versions.
