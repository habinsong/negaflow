# Negative response

[Docs home](../README.md)

## MAIN/PRINT and CS

The default is `MAIN` with Auto Balance on. The switch is described in [Chroma Engine](../product/CHROMA_ENGINE.md).

**Auto Balance ON.** Each channel uses its densest 0.2% scene percentile with a 1.8D range limit, followed by the `shoulder-print-response-v4` curve and muted-scene vibrance. Film presets multiply the measured range by their relative channel factors. The 1.8D limit is a rendering safeguard, not a measured property of every film, and it can affect dense negatives.

**Auto Balance OFF.** The same v4 curve with a fixed nominal range (color 1.55D, B&W 2.17D), multiplied by preset factors when a preset is selected. Scene range normalization and muted-scene vibrance are skipped. For color negatives, OFF also multiplies a channel range calibration for the scanner and film. It is the median of at least three frames with a valid measurement from the same roll, or from the same scan folder when no roll is set, and once chosen it stays on each frame. With fewer frames or mixed film, the three channels keep the same range. Equal transmittance with the same base and settings then gives the same result across a roll.

ON can change both brightness and color with scene content. Neither mode establishes measured film color accuracy.

Scene measurements are cached while manual sliders change. On Windows the preview inversion and vibrance run on D3D and export runs on the CPU.

## Other targets and RAW

Explicit scanner targets keep scene analysis and the fixed `shoulder-print-response-v4` primitive. Scene analysis has no universal 1.8D cap. A stock preset uses fixed relative factors and does not silently normalize each frame.

Both platforms decode negative camera RAW with LibRaw `output_color=0`, linear transfer and unit channel multipliers. Film-base measurement and inversion run on demosaiced camera RGB, and `rgb_cam` then maps the positive into linear sRGB. Capture white balance, automatic brightness and scene-dependent maximum adjustment are disabled. Preview, defect caches and export keep the deferred matrix. Digital-photo rendering is separate. Unsupported native output fails instead of silently using a matrix-processed negative. This order does not replace a measured camera, light and film calibration. Raw TIFF and baked-source TIFF are uninverted working-RGB images, so their color matrix is applied at that output boundary.

### Unbundled CLI RAW setup

The app bundle carries its decoder. For an unbundled macOS CLI or tests, build the same library and set its absolute path before starting the process.

```bash
bash negaflow-mac/scripts/build-libraw.sh
export NEGAFLOW_LIBRAW_LIBRARY="$PWD/build/libraw/$(uname -m)/libraw.dylib"
```

## Validation and sources

`NegativeAutoBalanceTests` checks the range, curve and vibrance combination, OFF and cache reuse. The Windows tests check the range cap, preset factors, OFF and the CPU/D3D RAW inversion order.

`FixedNegativeResponseTests` keeps the v6 model regressions used by EXPIRED. Its zero frame variation and idealized forward-model colors do not validate the MAIN/CS response or real-film color accuracy. Renderer and thumbnail identifiers keep current results apart from older cached previews.

- [Kodak H-740](https://www.kodak.com/content/products-brochures/Film/Basic-Photographic-Sensitometry-Workbook.pdf)
- [Kodak VISION3 scanning](https://www.kodak.com/content/products-brochures/Film/Scanning-Recommendations-for-Extended-Dynamic-Range-Camera-Films-EN.pdf)
- [Apple RAW linear processing](https://developer.apple.com/videos/play/wwdc2021/10160/)
- [Apple RAW tone](https://developer.apple.com/documentation/coreimage/cirawfilter/localtonemapamount)
- [LibRaw parameters](https://www.libraw.org/docs/API-datastruct-eng.html)
